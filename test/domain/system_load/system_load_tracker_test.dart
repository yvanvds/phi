import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/system_load/system_load.dart';
import 'package:phi/domain/system_load/system_load_level.dart';
import 'package:phi/domain/system_load/system_load_tracker.dart';
import 'package:phi/domain/system_load/thread_cpu_usage.dart';
import 'package:phi/platform/thread_cpu/thread_cpu_reading.dart';
import 'package:phi/platform/thread_cpu/thread_cpu_snapshot.dart';

ThreadCpuSnapshot _at(int ms, Map<int, (String, int)> threads) =>
    ThreadCpuSnapshot(
      timestamp: Duration(milliseconds: ms),
      threads: [
        for (final MapEntry(key: id, value: (name, cpuMs)) in threads.entries)
          ThreadCpuReading(
            id: id,
            name: name,
            cpuTime: Duration(milliseconds: cpuMs),
          ),
      ],
    );

void main() {
  test('the first snapshot only sets the baseline', () {
    final tracker = SystemLoadTracker(logicalCores: 4);
    final load = tracker.add(_at(0, {1: ('a', 500)}));
    expect(load, same(SystemLoad.pending));
    expect(load.available, isTrue);
    expect(load.level, SystemLoadLevel.unknown);
  });

  test('per-thread percent of one core over the window, busiest first', () {
    final tracker = SystemLoadTracker(logicalCores: 24)
      ..add(_at(0, {1: ('1.raster', 1000), 2: ('phi', 0), 3: ('swarm', 0)}));

    final load = tracker.add(
      _at(1000, {1: ('1.raster', 1640), 2: ('phi', 280), 3: ('swarm', 910)}),
    );

    expect(load.threads, const [
      ThreadCpuUsage(id: 3, name: 'swarm', percent: 91),
      ThreadCpuUsage(id: 1, name: '1.raster', percent: 64),
      ThreadCpuUsage(id: 2, name: 'phi', percent: 28),
    ]);
    expect(load.busiest!.name, 'swarm');
    expect(load.level, SystemLoadLevel.saturated);
    expect(load.logicalCores, 24);
    // 1830 ms of CPU in 1 s spread over 24 cores is 7.625 % — the average
    // that hides a saturated thread.
    expect(load.processPercent, closeTo(7.625, 1e-9));
  });

  test('a window of half a second doubles the per-ms rate', () {
    final tracker = SystemLoadTracker(logicalCores: 1)
      ..add(_at(1000, {1: ('a', 0)}));
    expect(tracker.add(_at(1500, {1: ('a', 100)})).threads.single.percent, 20);
  });

  test('a thread born inside the window counts all its CPU time', () {
    final tracker = SystemLoadTracker(logicalCores: 2)
      ..add(_at(0, {1: ('a', 0)}));
    final load = tracker.add(_at(1000, {1: ('a', 0), 9: ('new', 300)}));
    expect(
      load.threads.first,
      const ThreadCpuUsage(id: 9, name: 'new', percent: 30),
    );
  });

  test('a reused id whose time went backwards counts from zero', () {
    final tracker = SystemLoadTracker(logicalCores: 1)
      ..add(_at(0, {5: ('old', 9000)}));
    final load = tracker.add(_at(1000, {5: ('fresh', 200)}));
    expect(load.threads.single.percent, 20);
    expect(load.threads.single.name, 'fresh');
  });

  test('a thread that exited drops out', () {
    final tracker = SystemLoadTracker(logicalCores: 1)
      ..add(_at(0, {1: ('a', 0), 2: ('gone', 0)}));
    expect(tracker.add(_at(1000, {1: ('a', 10)})).threads.map((t) => t.id), [
      1,
    ]);
  });

  test('accounting jitter past one core is clamped to 100 %', () {
    final tracker = SystemLoadTracker(logicalCores: 1)
      ..add(_at(0, {1: ('a', 0)}));
    final load = tracker.add(_at(1000, {1: ('a', 1010)}));
    expect(load.threads.single.percent, 100);
    expect(load.processPercent, 100);
  });

  test('a window that did not advance yields pending', () {
    final tracker = SystemLoadTracker(logicalCores: 1)
      ..add(_at(1000, {1: ('a', 0)}));
    expect(tracker.add(_at(1000, {1: ('a', 10)})), same(SystemLoad.pending));
  });

  test('reset starts a fresh window', () {
    final tracker = SystemLoadTracker(logicalCores: 1)
      ..add(_at(0, {1: ('a', 0)}))
      ..reset();
    expect(tracker.add(_at(1000, {1: ('a', 500)})), same(SystemLoad.pending));
    expect(tracker.add(_at(2000, {1: ('a', 600)})).threads.single.percent, 10);
  });

  test('ties keep a stable order by thread id', () {
    final tracker = SystemLoadTracker(logicalCores: 1)
      ..add(_at(0, {3: ('c', 0), 1: ('a', 0), 2: ('b', 0)}));
    final load = tracker.add(
      _at(1000, {3: ('c', 0), 1: ('a', 0), 2: ('b', 0)}),
    );
    expect(load.threads.map((t) => t.id), [1, 2, 3]);
  });
}
