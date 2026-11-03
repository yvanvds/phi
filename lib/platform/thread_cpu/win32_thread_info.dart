/// What the Win32 thread queries report for one thread (issue #24): its
/// `GetThreadTimes` kernel + user times and its `GetThreadDescription` name.
class Win32ThreadInfo {
  /// Info for one thread; times are in FILETIME units (100 ns).
  const Win32ThreadInfo({
    required this.kernelTime100ns,
    required this.userTime100ns,
    this.description,
  });

  /// Time spent in kernel mode, in 100-nanosecond units.
  final int kernelTime100ns;

  /// Time spent in user mode, in 100-nanosecond units.
  final int userTime100ns;

  /// The thread's description, or `null` when none is set or the OS predates
  /// `GetThreadDescription` (Windows 10 1607).
  final String? description;
}
