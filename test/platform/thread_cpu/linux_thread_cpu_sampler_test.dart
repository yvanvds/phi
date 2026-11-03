import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/platform/thread_cpu/io_proc_task_reader.dart';
import 'package:phi/platform/thread_cpu/linux_clock_ticks.dart';
import 'package:phi/platform/thread_cpu/linux_thread_cpu_sampler.dart';
import 'package:phi/platform/thread_cpu/proc_task_reader.dart';

/// A stat line with [comm] and the given utime / stime (fields 14 / 15).
String _stat(int tid, String comm, {int utime = 0, int stime = 0}) =>
    '$tid ($comm) S 1 1 1 0 -1 4194560 100 0 0 0 $utime $stime 0 0 20 0 '
    '40 0 12345 1000000 500 18446744073709551615 1 1 0 0 0 0 0 0 0 0 0 0 '
    '17 3 0 0 0 0 0\n';

class _FakeProc implements ProcTaskReader {
  _FakeProc(this.stats, {Map<String, String>? comms}) : comms = comms ?? {};

  final Map<String, String?> stats;
  final Map<String, String> comms;

  @override
  List<String> taskIds() => stats.keys.toList();

  @override
  String? readStat(String taskId) => stats[taskId];

  @override
  String? readComm(String taskId) => comms[taskId];
}

void main() {
  group('LinuxThreadCpuSampler.parseStat', () {
    test('reads comm and utime + stime', () {
      final parsed = LinuxThreadCpuSampler.parseStat(
        _stat(42, '1.raster', utime: 120, stime: 30),
      );
      expect(parsed, isNotNull);
      expect(parsed!.comm, '1.raster');
      expect(parsed.ticks, 150);
    });

    test('a comm holding spaces and parentheses does not shift the fields', () {
      final parsed = LinuxThreadCpuSampler.parseStat(
        _stat(7, 'a) b (c', utime: 5, stime: 6),
      );
      expect(parsed!.comm, 'a) b (c');
      expect(parsed.ticks, 11);
    });

    test('malformed lines are rejected', () {
      expect(LinuxThreadCpuSampler.parseStat(''), isNull);
      expect(LinuxThreadCpuSampler.parseStat('12 (x) S 1 2 3'), isNull);
      expect(
        LinuxThreadCpuSampler.parseStat(
          _stat(1, 'x').replaceFirst(' 0 0 20 ', ' zz 0 20 '),
        ),
        isNotNull,
        reason: 'only utime / stime need to be numbers',
      );
    });
  });

  group('LinuxThreadCpuSampler.sample', () {
    test('converts ticks to CPU time, names from comm, stamps the clock', () {
      final sampler = LinuxThreadCpuSampler(
        reader: _FakeProc(
          {
            '100': _stat(100, 'phi', utime: 250, stime: 50),
            '101': _stat(101, '1.ui', utime: 10),
          },
          comms: {'100': 'phi\n', '101': '1.ui\n'},
        ),
        clockTicksPerSecond: 100,
        logicalCores: 24,
        elapsed: () => const Duration(seconds: 9),
      );

      final snapshot = sampler.sample();

      expect(sampler.logicalCores, 24);
      expect(snapshot.timestamp, const Duration(seconds: 9));
      expect(snapshot.threads.map((t) => t.id), [100, 101]);
      expect(snapshot.threads.map((t) => t.name), ['phi', '1.ui']);
      expect(snapshot.threads.first.cpuTime, const Duration(seconds: 3));
      expect(snapshot.threads.last.cpuTime, const Duration(milliseconds: 100));
    });

    test('falls back to the stat comm when comm is unreadable or blank', () {
      final sampler = LinuxThreadCpuSampler(
        reader: _FakeProc(
          {'5': _stat(5, 'from-stat'), '6': _stat(6, 'also-stat')},
          comms: {'6': '  \n'},
        ),
        clockTicksPerSecond: 100,
        logicalCores: 1,
        elapsed: () => Duration.zero,
      );

      expect(sampler.sample().threads.map((t) => t.name), [
        'from-stat',
        'also-stat',
      ]);
    });

    test('skips a thread that vanished, a malformed stat, a non-tid entry', () {
      final sampler = LinuxThreadCpuSampler(
        reader: _FakeProc({
          '1': _stat(1, 'alive', utime: 1),
          '2': null, // exited between the listing and the read
          '3': 'garbage',
          'self': _stat(4, 'not-a-tid'),
        }),
        clockTicksPerSecond: 100,
        logicalCores: 1,
        elapsed: () => Duration.zero,
      );

      expect(sampler.sample().threads.map((t) => t.id), [1]);
    });
  });

  group('IoProcTaskReader', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('proc_task'));
    tearDown(() => root.deleteSync(recursive: true));

    test('lists task directories and reads their stat + comm', () {
      Directory('${root.path}/321').createSync();
      File('${root.path}/321/stat').writeAsStringSync(_stat(321, 'w'));
      File('${root.path}/321/comm').writeAsStringSync('w\n');
      final reader = IoProcTaskReader(root: root.path);

      expect(reader.taskIds(), ['321']);
      expect(reader.readStat('321'), startsWith('321 (w)'));
      expect(reader.readComm('321'), 'w\n');
      expect(reader.readStat('999'), isNull, reason: 'a thread that exited');
    });
  });

  test('samples this very process from the real /proc', () {
    expect(LinuxClockTicks.perSecond(), greaterThan(0));
    final sampler = LinuxThreadCpuSampler();
    final snapshot = sampler.sample();

    expect(sampler.logicalCores, Platform.numberOfProcessors);
    expect(snapshot.threads, isNotEmpty);
    expect(snapshot.threads.map((t) => t.id), contains(pid));
    expect(snapshot.threads.every((t) => t.name.isNotEmpty), isTrue);
    expect(
      snapshot.threads.any((t) => t.cpuTime > Duration.zero),
      isTrue,
      reason: 'a running test process has spent CPU somewhere',
    );
  }, skip: Platform.isLinux ? false : 'Linux /proc only');
}
