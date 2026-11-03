import 'package:phi/platform/thread_cpu/thread_cpu_reading.dart';
import 'package:phi/platform/thread_cpu/thread_cpu_sampler.dart';
import 'package:phi/platform/thread_cpu/thread_cpu_snapshot.dart';

/// A [ThreadCpuSampler] whose threads run at scripted rates (issue #24).
///
/// Each [sample] advances its own clock by [step] and charges every thread in
/// [rates] its percent of that step, so the load a tracker derives is exact and
/// independent of how late a real timer fired.
class ScriptedThreadCpuSampler implements ThreadCpuSampler {
  ScriptedThreadCpuSampler({
    this.logicalCores = 24,
    this.step = const Duration(seconds: 1),
    Map<int, ({String name, double percent})>? rates,
  }) : rates = rates ?? {};

  @override
  final int logicalCores;

  /// Simulated time between two samples.
  final Duration step;

  /// Thread id → name and percent of one core it runs at from now on. Edit it
  /// between samples to change the load; remove an id to end that thread.
  final Map<int, ({String name, double percent})> rates;

  /// When set, the next [sample] throws it.
  Object? failWith;

  /// How many snapshots were taken.
  int samples = 0;

  Duration _now = Duration.zero;
  final Map<int, Duration> _cpu = {};

  @override
  ThreadCpuSnapshot sample() {
    final failure = failWith;
    if (failure != null) throw failure;
    if (samples > 0) {
      _now += step;
      for (final MapEntry(key: id, value: rate) in rates.entries) {
        _cpu[id] =
            (_cpu[id] ?? Duration.zero) +
            Duration(
              microseconds: (step.inMicroseconds * rate.percent / 100).round(),
            );
      }
    }
    samples++;
    return ThreadCpuSnapshot(
      timestamp: _now,
      threads: [
        for (final MapEntry(key: id, value: rate) in rates.entries)
          ThreadCpuReading(
            id: id,
            name: rate.name,
            cpuTime: _cpu[id] ?? Duration.zero,
          ),
      ],
    );
  }
}
