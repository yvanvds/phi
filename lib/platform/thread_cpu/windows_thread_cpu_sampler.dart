import 'dart:io';

import 'kernel32_thread_api.dart';
import 'monotonic_clock.dart';
import 'thread_cpu_reading.dart';
import 'thread_cpu_sampler.dart';
import 'thread_cpu_snapshot.dart';
import 'win32_thread_api.dart';

/// [ThreadCpuSampler] for Windows (issue #24): enumerates the process's threads
/// through Toolhelp, reads each one's kernel + user time with `GetThreadTimes`
/// and its name with `GetThreadDescription`.
class WindowsThreadCpuSampler implements ThreadCpuSampler {
  /// Samples through [api] (the real `kernel32` by default). [logicalCores]
  /// defaults to `Platform.numberOfProcessors`; [elapsed] is the monotonic clock
  /// stamped on each snapshot.
  WindowsThreadCpuSampler({
    Win32ThreadApi? api,
    int? logicalCores,
    Duration Function()? elapsed,
  }) : _api = api ?? Kernel32ThreadApi(),
       logicalCores = logicalCores ?? Platform.numberOfProcessors,
       _elapsed = elapsed ?? MonotonicClock.start();

  final Win32ThreadApi _api;
  final Duration Function() _elapsed;

  @override
  final int logicalCores;

  @override
  ThreadCpuSnapshot sample() {
    final timestamp = _elapsed();
    final threads = <ThreadCpuReading>[];
    for (final id in _api.currentProcessThreadIds()) {
      final info = _api.queryThread(id);
      if (info == null) continue;
      final total100ns = info.kernelTime100ns + info.userTime100ns;
      threads.add(
        ThreadCpuReading(
          id: id,
          name: info.description?.trim() ?? '',
          // FILETIME counts 100 ns intervals: ten per microsecond.
          cpuTime: Duration(microseconds: total100ns ~/ 10),
        ),
      );
    }
    return ThreadCpuSnapshot(timestamp: timestamp, threads: threads);
  }
}
