import 'win32_thread_info.dart';

/// The Win32 calls a [WindowsThreadCpuSampler] makes (issue #24), behind an
/// interface so the sampler is unit-testable on any OS. `Kernel32ThreadApi` is
/// the FFI implementation.
abstract interface class Win32ThreadApi {
  /// The ids of every thread owned by the current process — a
  /// `CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD)` walk with `Thread32First` /
  /// `Thread32Next`, filtered on `GetCurrentProcessId`. Throws if the snapshot
  /// itself cannot be taken.
  List<int> currentProcessThreadIds();

  /// `OpenThread` + `GetThreadTimes` + `GetThreadDescription` for [threadId],
  /// or `null` if the thread exited or cannot be opened.
  Win32ThreadInfo? queryThread(int threadId);
}
