import 'dart:io';

import 'linux_thread_cpu_sampler.dart';
import 'thread_cpu_sampler.dart';
import 'windows_thread_cpu_sampler.dart';

/// Picks the [ThreadCpuSampler] for the OS Phi is running on (issue #24).
class HostThreadCpuSampler {
  HostThreadCpuSampler._();

  /// The sampler for this OS, or `null` where Phi has none (anything but Linux
  /// and Windows) or the OS facilities could not be bound — the `SYS` chip then
  /// reads "unavailable" rather than the app failing to start.
  static ThreadCpuSampler? create() {
    try {
      if (Platform.isLinux) return LinuxThreadCpuSampler();
      if (Platform.isWindows) return WindowsThreadCpuSampler();
    } on Object {
      return null;
    }
    return null;
  }
}
