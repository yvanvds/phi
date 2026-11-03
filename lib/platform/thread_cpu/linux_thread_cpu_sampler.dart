import 'dart:io';

import 'io_proc_task_reader.dart';
import 'linux_clock_ticks.dart';
import 'monotonic_clock.dart';
import 'proc_task_reader.dart';
import 'thread_cpu_reading.dart';
import 'thread_cpu_sampler.dart';
import 'thread_cpu_snapshot.dart';

/// [ThreadCpuSampler] for Linux (issue #24): one reading per entry under
/// `/proc/self/task`, CPU time from the `utime` + `stime` fields of each
/// thread's `stat`, the name from its `comm`.
class LinuxThreadCpuSampler implements ThreadCpuSampler {
  /// Reads [reader] (the real `/proc/self/task` by default), converting clock
  /// ticks at [clockTicksPerSecond] (`sysconf(_SC_CLK_TCK)` by default).
  /// [logicalCores] defaults to `Platform.numberOfProcessors`; [elapsed] is the
  /// monotonic clock stamped on each snapshot (a running [Stopwatch] by
  /// default).
  LinuxThreadCpuSampler({
    ProcTaskReader? reader,
    int? clockTicksPerSecond,
    int? logicalCores,
    Duration Function()? elapsed,
  }) : _reader = reader ?? const IoProcTaskReader(),
       _ticksPerSecond = clockTicksPerSecond ?? LinuxClockTicks.perSecond(),
       logicalCores = logicalCores ?? Platform.numberOfProcessors,
       _elapsed = elapsed ?? MonotonicClock.start();

  final ProcTaskReader _reader;
  final int _ticksPerSecond;
  final Duration Function() _elapsed;

  @override
  final int logicalCores;

  /// Index of `utime` among the fields that follow the parenthesised `comm`
  /// (`state` is index 0, i.e. `stat` field 3; `utime` is field 14).
  static const int _utimeIndex = 14 - 3;

  /// Index of `stime` (`stat` field 15) on the same basis.
  static const int _stimeIndex = 15 - 3;

  @override
  ThreadCpuSnapshot sample() {
    final timestamp = _elapsed();
    final threads = <ThreadCpuReading>[];
    for (final taskId in _reader.taskIds()) {
      final id = int.tryParse(taskId);
      if (id == null) continue;
      final stat = _reader.readStat(taskId);
      if (stat == null) continue;
      final parsed = parseStat(stat);
      if (parsed == null) continue;
      final comm = _reader.readComm(taskId)?.trim();
      final ticks = parsed.ticks;
      threads.add(
        ThreadCpuReading(
          id: id,
          name: (comm == null || comm.isEmpty) ? parsed.comm : comm,
          cpuTime: Duration(
            microseconds:
                ticks * Duration.microsecondsPerSecond ~/ _ticksPerSecond,
          ),
        ),
      );
    }
    return ThreadCpuSnapshot(timestamp: timestamp, threads: threads);
  }

  /// Parses one `stat` line into its `comm` and `utime + stime` clock ticks,
  /// or `null` if it is malformed.
  ///
  /// `comm` sits in parentheses and may itself contain spaces or `)`, so the
  /// numeric fields are found after the *last* `)`, as `proc(5)` advises.
  static ({String comm, int ticks})? parseStat(String stat) {
    final open = stat.indexOf('(');
    final close = stat.lastIndexOf(')');
    if (open < 0 || close < open) return null;
    final comm = stat.substring(open + 1, close);
    final rest = stat.substring(close + 1).trim().split(RegExp(r'\s+'));
    if (rest.length <= _stimeIndex) return null;
    final utime = int.tryParse(rest[_utimeIndex]);
    final stime = int.tryParse(rest[_stimeIndex]);
    if (utime == null || stime == null) return null;
    return (comm: comm, ticks: utime + stime);
  }
}
