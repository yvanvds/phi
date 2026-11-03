/// The `/proc/self/task` tree a [LinuxThreadCpuSampler] reads (issue #24),
/// behind an interface so the parsing is unit-testable with canned file
/// contents.
///
/// Every read returns `null` for a thread that exited between the directory
/// listing and the read — routine on a live process, not an error.
abstract interface class ProcTaskReader {
  /// The thread ids listed under `/proc/self/task`, as directory names.
  List<String> taskIds();

  /// The content of `/proc/self/task/<taskId>/stat`, or `null` if gone.
  String? readStat(String taskId);

  /// The content of `/proc/self/task/<taskId>/comm`, or `null` if gone.
  String? readComm(String taskId);
}
