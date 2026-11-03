import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'win32_thread_api.dart';
import 'win32_thread_info.dart';

/// The FFI [Win32ThreadApi] over `kernel32.dll` (issue #24).
///
/// `GetThreadDescription` only exists from Windows 10 1607 on; it is resolved
/// lazily and, where missing, every thread simply reports no name.
class Kernel32ThreadApi implements Win32ThreadApi {
  /// Opens `kernel32.dll` and binds the calls. Only constructible on Windows.
  Kernel32ThreadApi() : this._(DynamicLibrary.open('kernel32.dll'));

  Kernel32ThreadApi._(DynamicLibrary kernel32)
    : _createSnapshot = kernel32
          .lookupFunction<
            IntPtr Function(Uint32, Uint32),
            int Function(int, int)
          >('CreateToolhelp32Snapshot'),
      _thread32First = kernel32
          .lookupFunction<
            Int32 Function(IntPtr, Pointer<Uint32>),
            int Function(int, Pointer<Uint32>)
          >('Thread32First'),
      _thread32Next = kernel32
          .lookupFunction<
            Int32 Function(IntPtr, Pointer<Uint32>),
            int Function(int, Pointer<Uint32>)
          >('Thread32Next'),
      _getCurrentProcessId = kernel32
          .lookupFunction<Uint32 Function(), int Function()>(
            'GetCurrentProcessId',
          ),
      _openThread = kernel32
          .lookupFunction<
            IntPtr Function(Uint32, Int32, Uint32),
            int Function(int, int, int)
          >('OpenThread'),
      _getThreadTimes = kernel32
          .lookupFunction<
            Int32 Function(
              IntPtr,
              Pointer<Uint64>,
              Pointer<Uint64>,
              Pointer<Uint64>,
              Pointer<Uint64>,
            ),
            int Function(
              int,
              Pointer<Uint64>,
              Pointer<Uint64>,
              Pointer<Uint64>,
              Pointer<Uint64>,
            )
          >('GetThreadTimes'),
      _closeHandle = kernel32
          .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'CloseHandle',
          ),
      _localFree = kernel32
          .lookupFunction<IntPtr Function(IntPtr), int Function(int)>(
            'LocalFree',
          ),
      _getThreadDescription = _lookupDescription(kernel32);

  /// `TH32CS_SNAPTHREAD`.
  static const int _snapThread = 0x00000004;

  /// `THREAD_QUERY_LIMITED_INFORMATION` — enough for both `GetThreadTimes` and
  /// `GetThreadDescription`, and grantable on threads we do not fully own.
  static const int _threadQueryLimitedInformation = 0x0800;

  /// `INVALID_HANDLE_VALUE`.
  static const int _invalidHandle = -1;

  /// `sizeof(THREADENTRY32)`: seven 32-bit fields.
  static const int _threadEntrySize = 7 * 4;

  // THREADENTRY32 field offsets, in 32-bit words.
  static const int _entryDwSize = 0;
  static const int _entryThreadId = 2;
  static const int _entryOwnerProcessId = 3;

  final int Function(int, int) _createSnapshot;
  final int Function(int, Pointer<Uint32>) _thread32First;
  final int Function(int, Pointer<Uint32>) _thread32Next;
  final int Function() _getCurrentProcessId;
  final int Function(int, int, int) _openThread;
  final int Function(
    int,
    Pointer<Uint64>,
    Pointer<Uint64>,
    Pointer<Uint64>,
    Pointer<Uint64>,
  )
  _getThreadTimes;
  final int Function(int) _closeHandle;
  final int Function(int) _localFree;
  final int Function(int, Pointer<Pointer<Utf16>>)? _getThreadDescription;

  static int Function(int, Pointer<Pointer<Utf16>>)? _lookupDescription(
    DynamicLibrary kernel32,
  ) {
    try {
      return kernel32.lookupFunction<
        Int32 Function(IntPtr, Pointer<Pointer<Utf16>>),
        int Function(int, Pointer<Pointer<Utf16>>)
      >('GetThreadDescription');
    } on ArgumentError {
      return null; // Pre-1607 Windows: no thread descriptions.
    }
  }

  @override
  List<int> currentProcessThreadIds() {
    final snapshot = _createSnapshot(_snapThread, 0);
    if (snapshot == _invalidHandle || snapshot == 0) {
      throw StateError('CreateToolhelp32Snapshot failed');
    }
    final entry = calloc<Uint32>(_threadEntrySize ~/ 4);
    try {
      entry[_entryDwSize] = _threadEntrySize;
      final pid = _getCurrentProcessId();
      final ids = <int>[];
      var more = _thread32First(snapshot, entry) != 0;
      while (more) {
        if (entry[_entryOwnerProcessId] == pid) ids.add(entry[_entryThreadId]);
        entry[_entryDwSize] = _threadEntrySize;
        more = _thread32Next(snapshot, entry) != 0;
      }
      return ids;
    } finally {
      calloc.free(entry);
      _closeHandle(snapshot);
    }
  }

  @override
  Win32ThreadInfo? queryThread(int threadId) {
    final handle = _openThread(_threadQueryLimitedInformation, 0, threadId);
    if (handle == 0) return null;
    final times = calloc<Uint64>(4);
    try {
      final ok = _getThreadTimes(
        handle,
        times, // creation
        times + 1, // exit
        times + 2, // kernel
        times + 3, // user
      );
      if (ok == 0) return null;
      return Win32ThreadInfo(
        kernelTime100ns: times[2],
        userTime100ns: times[3],
        description: _description(handle),
      );
    } finally {
      calloc.free(times);
      _closeHandle(handle);
    }
  }

  String? _description(int handle) {
    final getDescription = _getThreadDescription;
    if (getDescription == null) return null;
    final out = calloc<Pointer<Utf16>>();
    try {
      // HRESULT: negative is failure.
      if (getDescription(handle, out) < 0) return null;
      final text = out.value;
      if (text == nullptr) return null;
      try {
        final name = text.toDartString();
        return name.isEmpty ? null : name;
      } finally {
        _localFree(text.address);
      }
    } finally {
      calloc.free(out);
    }
  }
}
