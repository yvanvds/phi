import 'package:phi/engine/bridge/patch_clock.dart';

/// In-memory [PatchClock] (issue #529): records every tempo it is given and
/// whether it was disposed. The beat never advances on its own; a test sets
/// [beatPosition] when it needs one.
class FakePatchClock implements PatchClock {
  FakePatchClock(this.name, {required double tempo, this.publishedAt = 0})
    : tempos = [tempo];

  /// How many gateway calls had been logged when this clock was published —
  /// lets a test check it came before a patch was created.
  final int publishedAt;

  @override
  final String name;

  /// Every tempo this clock was given, the creation tempo first.
  final List<double> tempos;

  bool disposed = false;

  @override
  double beatPosition = 0;

  @override
  double get currentTempo => tempos.last;

  @override
  void setTempo(double bpm) => tempos.add(bpm);

  @override
  void dispose() => disposed = true;
}
