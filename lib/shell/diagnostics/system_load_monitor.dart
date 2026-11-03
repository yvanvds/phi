import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/system_load/system_load.dart';
import '../../domain/system_load/system_load_tracker.dart';
import '../../platform/thread_cpu/thread_cpu_sampler.dart';

/// Polls a [ThreadCpuSampler] about once a second and publishes the per-thread
/// [SystemLoad] the status bar's `SYS` chip shows (issue #24).
///
/// Independent of the engine's 16 ms telemetry tick on purpose: a thread
/// percentage needs a window long enough to hold many scheduler quanta, and a
/// procfs / Toolhelp walk every frame would itself show up in the numbers.
///
/// With no sampler (an OS Phi has none for, or a test that wires none) the
/// load stays [SystemLoad.unavailable] and no timer runs. A sampler that throws
/// is treated the same way: the monitor stops rather than retrying every
/// second into the same failure.
class SystemLoadMonitor {
  /// Starts polling [sampler] every [interval]; `null` means unavailable.
  SystemLoadMonitor({
    ThreadCpuSampler? sampler,
    this.interval = const Duration(seconds: 1),
  }) : _sampler = sampler,
       _load = ValueNotifier(
         sampler == null ? SystemLoad.unavailable : SystemLoad.pending,
       ) {
    final active = sampler;
    if (active == null) return;
    _tracker = SystemLoadTracker(logicalCores: active.logicalCores);
    // Take the baseline now so the first real figure lands one interval in.
    _sample();
    if (_load.value.available) {
      _timer = Timer.periodic(interval, (_) => _sample());
    }
  }

  final ThreadCpuSampler? _sampler;

  /// How often a snapshot is taken — also the measuring window.
  final Duration interval;

  SystemLoadTracker? _tracker;
  Timer? _timer;
  final ValueNotifier<SystemLoad> _load;

  /// The latest measured window; rebuilds the `SYS` chip and popover.
  ValueListenable<SystemLoad> get load => _load;

  void _sample() {
    final sampler = _sampler;
    final tracker = _tracker;
    if (sampler == null || tracker == null) return;
    try {
      _load.value = tracker.add(sampler.sample());
    } on Object {
      _timer?.cancel();
      _timer = null;
      _load.value = SystemLoad.unavailable;
    }
  }

  /// Stops polling and releases the notifier.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _load.dispose();
  }
}
