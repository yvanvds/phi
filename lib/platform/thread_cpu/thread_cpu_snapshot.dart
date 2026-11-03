import 'thread_cpu_reading.dart';

/// Every thread of the Phi process at one instant (issue #24): what a
/// [ThreadCpuSampler] hands back per sample.
class ThreadCpuSnapshot {
  /// A snapshot taken at [timestamp] holding [threads].
  const ThreadCpuSnapshot({required this.timestamp, required this.threads});

  /// When the snapshot was taken, on a monotonic clock owned by the sampler.
  /// Only differences between two snapshots of the same sampler mean anything.
  final Duration timestamp;

  /// One reading per thread alive when the snapshot was taken.
  final List<ThreadCpuReading> threads;
}
