import 'package:flutter/foundation.dart';

import 'tempo_source.dart';

/// A hand-driven [TempoSource] — the first gesture behind the tempo-source seam
/// (issue #104).
///
/// A bipolar fader riding one domain's tempo: [position] runs `[-1, 1]` with `0`
/// at rest (no bend), and the fader contributes `position * bendRange` BPM. Pull
/// it up to run the domain hot, down to drag it — so two time streams (one
/// played, one static) can be bent against each other by hand. This is the
/// minimal gesture that lets the polytemporal feel be *heard* before richer
/// sources are designed; those compose behind the same seam later.
///
/// At rest ([position] `== 0`) it does not modulate, so the seam adds nothing
/// and touches no FFI — the fader is free until a hand moves it. A
/// [ChangeNotifier] so a [PhiFader] (or code) can drive it and the seam re-ramp
/// the clock live on each nudge.
class FaderTempoSource extends ChangeNotifier implements TempoSource {
  FaderTempoSource({double bendRange = 40, double position = 0})
    : assert(bendRange > 0, 'bendRange must be a positive BPM span'),
      _bendRange = bendRange,
      _position = position.clamp(-1.0, 1.0);

  final double _bendRange;

  /// The BPM offset applied at full deflection ([position] `== ±1`). A
  /// deliberately wide default (±40 BPM) so the bend is audible against a
  /// typical tempo; the span itself is fixed for the life of the source.
  double get bendRange => _bendRange;

  double _position;

  /// The fader position in `[-1, 1]`; `0` at rest. Assigning outside the range
  /// clamps. A no-op assignment notifies nothing, so parking the fader where it
  /// already sits costs nothing downstream.
  double get position => _position;
  set position(double value) {
    final next = value.clamp(-1.0, 1.0);
    if (next == _position) return;
    _position = next;
    notifyListeners();
  }

  @override
  double get offset => _position * _bendRange;

  @override
  bool get isModulating => _position != 0;
}
