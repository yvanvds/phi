// Measurement harness for phi#15 — CPU stays elevated after stopping the
// built-in audio test signal.
//
// Initialises YSE, samples `System.cpuLoad` across four phases:
//   1. idle (before play)        — baseline
//   2. playing  (audioTest=true) — expected: rises moderately
//   3. after stop (audioTest=false) — bug: stays elevated
//   4. extended idle             — does it recover, drift further, plateau?
//
// Run from the phi repo root with libyse.dll discoverable:
//   $env:YSE_DLL_PATH = "D:\dart-yse\third_party\yse-soundengine\build\bin"
//   dart run tool/measure_audio_test_cpu.dart
//
// Outputs min / mean / max cpuLoad per phase as a markdown table suitable for
// pasting into a GitHub issue.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:yse/yse.dart';

const Duration _phaseDuration = Duration(seconds: 5);
const Duration _sampleInterval = Duration(milliseconds: 100);
const Duration _updateInterval = Duration(milliseconds: 16);

class _PhaseStats {
  _PhaseStats(this.name);

  final String name;
  final List<double> samples = [];

  double get min => samples.reduce((a, b) => a < b ? a : b);
  double get max => samples.reduce((a, b) => a > b ? a : b);
  double get mean => samples.reduce((a, b) => a + b) / samples.length;
}

Future<_PhaseStats> _samplePhase(String name, System sys) async {
  // `sys.update()` is driven by the auto-update timer started in [main]; we
  // just yield to the event loop and sample cpuLoad at each tick.
  final stats = _PhaseStats(name);
  final deadline = DateTime.now().add(_phaseDuration);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(_sampleInterval);
    stats.samples.add(sys.cpuLoad);
  }
  return stats;
}

Future<void> main() async {
  final sys = System.instance;
  print('libYSE ${System.version}');
  sys.init();
  sys.startUpdateTimer(_updateInterval);

  // Give the engine a beat to settle before measuring.
  await Future<void>.delayed(const Duration(milliseconds: 500));

  final phases = <_PhaseStats>[];

  phases.add(await _samplePhase('idle (before play)', sys));

  sys.audioTest = true;
  phases.add(await _samplePhase('playing', sys));

  sys.audioTest = false;
  phases.add(await _samplePhase('after stop', sys));

  phases.add(await _samplePhase('extended idle', sys));

  sys.close();

  print('');
  print('| phase | samples | min | mean | max |');
  print('| --- | ---: | ---: | ---: | ---: |');
  for (final p in phases) {
    String pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
    print(
      '| ${p.name} | ${p.samples.length} '
      '| ${pct(p.min)} | ${pct(p.mean)} | ${pct(p.max)} |',
    );
  }
  print('');
  print('missed callbacks at end: ${sys.missedCallbacks}');

  exitCode = 0;
}
