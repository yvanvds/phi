import '../../platform/thread_cpu/thread_cpu_snapshot.dart';
import 'system_load.dart';
import 'thread_cpu_usage.dart';

/// Turns successive [ThreadCpuSnapshot]s into a [SystemLoad] (issue #24): each
/// thread's CPU-time delta over the wall-time delta between two snapshots.
///
/// Pure arithmetic — the OS reads happen in the `ThreadCpuSampler`, the polling
/// in the shell's `SystemLoadMonitor`.
class SystemLoadTracker {
  /// A tracker normalising the whole-process figure over [logicalCores].
  SystemLoadTracker({required this.logicalCores});

  /// The logical core count the whole-process percent is divided over.
  final int logicalCores;

  ThreadCpuSnapshot? _previous;

  /// Folds in [snapshot] and returns the load over the window since the last
  /// one — [SystemLoad.pending] for the first snapshot (no window yet) or one
  /// that did not move forward in time.
  ///
  /// A thread absent from the previous snapshot started inside the window, so
  /// all of its CPU time counts. A thread whose CPU time went *backwards* is a
  /// reused id (the old thread exited, a new one took its id) and is treated
  /// the same way. A thread that exited inside the window drops out.
  SystemLoad add(ThreadCpuSnapshot snapshot) {
    final previous = _previous;
    _previous = snapshot;
    if (previous == null) return SystemLoad.pending;
    final window = snapshot.timestamp - previous.timestamp;
    if (window <= Duration.zero) return SystemLoad.pending;

    final before = {for (final t in previous.threads) t.id: t.cpuTime};
    final windowUs = window.inMicroseconds;
    var totalUs = 0;
    final threads = <ThreadCpuUsage>[];
    for (final thread in snapshot.threads) {
      final earlier = before[thread.id];
      var deltaUs = thread.cpuTime.inMicroseconds;
      if (earlier != null && earlier <= thread.cpuTime) {
        deltaUs -= earlier.inMicroseconds;
      }
      totalUs += deltaUs;
      threads.add(
        ThreadCpuUsage(
          id: thread.id,
          name: thread.name,
          // A thread cannot outrun one core; clamp the sampling jitter (the
          // OS accounts CPU time in ticks / quanta) that can push it past.
          percent: (deltaUs * 100 / windowUs).clamp(0, 100).toDouble(),
        ),
      );
    }
    threads.sort((a, b) {
      final byLoad = b.percent.compareTo(a.percent);
      return byLoad != 0 ? byLoad : a.id.compareTo(b.id);
    });
    final cores = logicalCores < 1 ? 1 : logicalCores;
    return SystemLoad(
      threads: List.unmodifiable(threads),
      processPercent: (totalUs * 100 / (windowUs * cores))
          .clamp(0, 100)
          .toDouble(),
      logicalCores: cores,
    );
  }

  /// Forgets the last snapshot, so the next [add] starts a fresh window.
  void reset() => _previous = null;
}
