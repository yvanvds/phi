import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/system_load/system_load.dart';
import 'package:phi/domain/system_load/system_load_level.dart';
import 'package:phi/domain/system_load/thread_cpu_usage.dart';

void main() {
  group('SystemLoadLevel.forPercent', () {
    test('ok below 60, busy from 60, saturated from 85', () {
      expect(SystemLoadLevel.forPercent(0), SystemLoadLevel.ok);
      expect(SystemLoadLevel.forPercent(59.9), SystemLoadLevel.ok);
      expect(SystemLoadLevel.forPercent(60), SystemLoadLevel.busy);
      expect(SystemLoadLevel.forPercent(84.9), SystemLoadLevel.busy);
      expect(SystemLoadLevel.forPercent(85), SystemLoadLevel.saturated);
      expect(SystemLoadLevel.forPercent(100), SystemLoadLevel.saturated);
    });
  });

  group('ThreadCpuUsage', () {
    test('label falls back to the thread id when unnamed', () {
      expect(
        const ThreadCpuUsage(id: 7, name: '1.ui', percent: 1).label,
        '1.ui',
      );
      expect(
        const ThreadCpuUsage(id: 7, name: '', percent: 1).label,
        'thread 7',
      );
    });
  });

  group('SystemLoad', () {
    test('unavailable and pending carry no threads and an unknown level', () {
      expect(SystemLoad.unavailable.available, isFalse);
      expect(SystemLoad.pending.available, isTrue);
      for (final load in [SystemLoad.unavailable, SystemLoad.pending]) {
        expect(load.threads, isEmpty);
        expect(load.busiest, isNull);
        expect(load.level, SystemLoadLevel.unknown);
      }
    });

    test('the level follows the busiest thread, not the average', () {
      const load = SystemLoad(
        threads: [
          ThreadCpuUsage(id: 1, name: 'a', percent: 70),
          ThreadCpuUsage(id: 2, name: 'b', percent: 1),
        ],
        processPercent: 3,
        logicalCores: 24,
      );
      expect(load.level, SystemLoadLevel.busy);
    });

    test('top keeps the N busiest threads that did measurable work', () {
      const load = SystemLoad(
        threads: [
          ThreadCpuUsage(id: 1, name: 'a', percent: 50),
          ThreadCpuUsage(id: 2, name: 'b', percent: 20),
          ThreadCpuUsage(id: 3, name: 'c', percent: 10),
          ThreadCpuUsage(id: 4, name: 'idle', percent: 0.05),
        ],
        processPercent: 4,
        logicalCores: 2,
      );
      expect(load.top(2).map((t) => t.id), [1, 2]);
      expect(load.top(10).map((t) => t.id), [1, 2, 3]);
    });
  });
}
