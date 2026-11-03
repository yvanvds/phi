/// The default monotonic time source the thread-CPU samplers stamp their
/// snapshots with (issue #24).
class MonotonicClock {
  MonotonicClock._();

  /// Starts a [Stopwatch] and returns a reader of its elapsed time — immune to
  /// wall-clock jumps, which would otherwise skew a sampling window.
  static Duration Function() start() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}
