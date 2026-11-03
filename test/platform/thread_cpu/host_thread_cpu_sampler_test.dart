import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/platform/thread_cpu/host_thread_cpu_sampler.dart';
import 'package:phi/platform/thread_cpu/linux_thread_cpu_sampler.dart';
import 'package:phi/platform/thread_cpu/windows_thread_cpu_sampler.dart';

void main() {
  test('picks the sampler for the running OS', () {
    final sampler = HostThreadCpuSampler.create();
    if (Platform.isLinux) {
      expect(sampler, isA<LinuxThreadCpuSampler>());
    } else if (Platform.isWindows) {
      expect(sampler, isA<WindowsThreadCpuSampler>());
    } else {
      expect(sampler, isNull);
    }
  });
}
