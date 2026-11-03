/// One OS thread's cumulative CPU time at the instant a [ThreadCpuSnapshot] was
/// taken (issue #24).
///
/// The figure is cumulative since the thread started — user plus kernel time —
/// so a single reading says nothing about load; the domain's
/// `SystemLoadTracker` turns two snapshots into per-thread percentages.
class ThreadCpuReading {
  /// A reading for the thread [id], named [name], that has used [cpuTime].
  const ThreadCpuReading({
    required this.id,
    required this.name,
    required this.cpuTime,
  });

  /// The OS thread id (Linux TID, Windows thread id). Unique among the threads
  /// alive at one instant; the OS may reuse it once a thread exits.
  final int id;

  /// The thread's name as the OS knows it — `comm` on Linux,
  /// `GetThreadDescription` on Windows. Empty when the thread was never named.
  final String name;

  /// User + kernel CPU time the thread has consumed since it started.
  final Duration cpuTime;
}
