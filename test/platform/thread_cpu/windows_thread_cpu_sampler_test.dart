import 'package:flutter_test/flutter_test.dart';
import 'package:phi/platform/thread_cpu/win32_thread_api.dart';
import 'package:phi/platform/thread_cpu/win32_thread_info.dart';
import 'package:phi/platform/thread_cpu/windows_thread_cpu_sampler.dart';

class _FakeWin32 implements Win32ThreadApi {
  _FakeWin32(this.threads);

  final Map<int, Win32ThreadInfo?> threads;
  Object? enumerationFailure;
  final queried = <int>[];

  @override
  List<int> currentProcessThreadIds() {
    final failure = enumerationFailure;
    if (failure != null) throw failure;
    return threads.keys.toList();
  }

  @override
  Win32ThreadInfo? queryThread(int threadId) {
    queried.add(threadId);
    return threads[threadId];
  }
}

void main() {
  test('sums kernel + user FILETIME units into CPU time, names from the '
      'description', () {
    final api = _FakeWin32({
      10: const Win32ThreadInfo(
        kernelTime100ns: 5000000, // 0.5 s
        userTime100ns: 15000000, // 1.5 s
        description: 'io.flutter.raster',
      ),
      11: const Win32ThreadInfo(kernelTime100ns: 10, userTime100ns: 0),
    });
    final sampler = WindowsThreadCpuSampler(
      api: api,
      logicalCores: 24,
      elapsed: () => const Duration(milliseconds: 1500),
    );

    final snapshot = sampler.sample();

    expect(sampler.logicalCores, 24);
    expect(snapshot.timestamp, const Duration(milliseconds: 1500));
    expect(snapshot.threads.map((t) => t.id), [10, 11]);
    expect(snapshot.threads.first.name, 'io.flutter.raster');
    expect(snapshot.threads.first.cpuTime, const Duration(seconds: 2));
    // An undescribed thread (PortAudio's callback today) reports no name.
    expect(snapshot.threads.last.name, '');
    expect(snapshot.threads.last.cpuTime, const Duration(microseconds: 1));
  });

  test('a thread that cannot be opened (exited) is skipped', () {
    final api = _FakeWin32({
      1: const Win32ThreadInfo(kernelTime100ns: 0, userTime100ns: 0),
      2: null,
    });
    final sampler = WindowsThreadCpuSampler(
      api: api,
      logicalCores: 1,
      elapsed: () => Duration.zero,
    );

    expect(sampler.sample().threads.map((t) => t.id), [1]);
    expect(api.queried, [1, 2]);
  });

  test('a failed thread enumeration propagates', () {
    final api = _FakeWin32({})..enumerationFailure = StateError('snapshot');
    final sampler = WindowsThreadCpuSampler(
      api: api,
      logicalCores: 1,
      elapsed: () => Duration.zero,
    );

    expect(sampler.sample, throwsStateError);
  });
}
