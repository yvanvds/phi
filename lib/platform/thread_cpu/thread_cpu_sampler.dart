import 'thread_cpu_snapshot.dart';

/// Reads the per-thread CPU time of the running Phi process (issue #24).
///
/// The OS-specific implementations live beside this interface
/// (`LinuxThreadCpuSampler` over `/proc/self/task`, `WindowsThreadCpuSampler`
/// over the Toolhelp + thread-times APIs); `HostThreadCpuSampler.create` picks
/// the one for the running OS. Tests supply a scripted fake.
abstract interface class ThreadCpuSampler {
  /// The number of logical processors the process can run on — the
  /// denominator that normalises the whole-process figure.
  int get logicalCores;

  /// Takes one snapshot of every thread in the process. Synchronous and cheap
  /// (a few dozen small reads); callers poll it about once a second. Throws if
  /// the OS refuses the enumeration as a whole — a single thread that vanished
  /// mid-sample is skipped, not an error.
  ThreadCpuSnapshot sample();
}
