import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/system_load/system_load.dart';
import 'package:phi/domain/system_load/system_load_level.dart';
import 'package:phi/shell/diagnostics/system_load_monitor.dart';

import '../../platform/thread_cpu/test_doubles/scripted_thread_cpu_sampler.dart';

void main() {
  test('no sampler: unavailable, nothing polled', () {
    fakeAsync((async) {
      final monitor = SystemLoadMonitor();
      expect(monitor.load.value, same(SystemLoad.unavailable));
      async.elapse(const Duration(seconds: 5));
      expect(async.pendingTimers, isEmpty);
      monitor.dispose();
    });
  });

  test('takes a baseline at once, then publishes a window per interval', () {
    fakeAsync((async) {
      final sampler = ScriptedThreadCpuSampler(
        rates: {
          1: (name: '1.raster', percent: 40),
          2: (name: 'swarm', percent: 91),
        },
      );
      final monitor = SystemLoadMonitor(sampler: sampler);
      expect(sampler.samples, 1, reason: 'baseline taken on construction');
      expect(monitor.load.value, same(SystemLoad.pending));

      async.elapse(const Duration(seconds: 1));
      final load = monitor.load.value;
      expect(load.busiest!.name, 'swarm');
      expect(load.busiest!.percent, closeTo(91, 1e-6));
      expect(load.level, SystemLoadLevel.saturated);
      expect(load.logicalCores, 24);

      sampler.rates[2] = (name: 'swarm', percent: 5);
      async.elapse(const Duration(seconds: 1));
      expect(monitor.load.value.busiest!.name, '1.raster');
      expect(monitor.load.value.level, SystemLoadLevel.ok);
      expect(sampler.samples, 3);

      monitor.dispose();
      expect(async.pendingTimers, isEmpty);
    });
  });

  test(
    'a sampler that throws turns the chip unavailable and stops polling',
    () {
      fakeAsync((async) {
        final sampler = ScriptedThreadCpuSampler(
          rates: {1: (name: 'a', percent: 10)},
        );
        final monitor = SystemLoadMonitor(sampler: sampler);
        async.elapse(const Duration(seconds: 1));
        expect(monitor.load.value.available, isTrue);

        sampler.failWith = StateError('enumeration refused');
        async.elapse(const Duration(seconds: 1));
        expect(monitor.load.value, same(SystemLoad.unavailable));
        expect(async.pendingTimers, isEmpty);
        monitor.dispose();
      });
    },
  );

  test('a sampler that fails on the baseline never starts a timer', () {
    fakeAsync((async) {
      final sampler = ScriptedThreadCpuSampler()..failWith = StateError('no');
      final monitor = SystemLoadMonitor(sampler: sampler);
      expect(monitor.load.value, same(SystemLoad.unavailable));
      expect(async.pendingTimers, isEmpty);
      monitor.dispose();
    });
  });
}
