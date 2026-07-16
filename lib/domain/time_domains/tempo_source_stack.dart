import 'package:flutter/foundation.dart';

import 'tempo_source.dart';

/// The tempo-source seam (issue #104): a domain's tempo input as a *list* of
/// [TempoSource]s summed at control rate.
///
/// A played domain's effective tempo is a base rate ([apply]'s argument) bent by
/// the sum of its sources' offsets. The list will almost always hold one entry
/// (today, a single fader), but modelling it as a summed stack now means future
/// sources — state-machine ramps, an LFO on time, spatial coupling, a
/// convergence autopilot — stack behind the same seam without a breaking rework
/// and without the engine ever learning about them (`docs/timing-architecture.md`
/// §3).
///
/// Zero idle cost: [isModulating] is `false` whenever every source rests, and
/// [apply] then returns the base tempo untouched — no offset, no clamp, nothing
/// to push. A [ChangeNotifier] that forwards each source's notifications, so the
/// player re-ramps the transport clock the instant any source moves.
class TempoSourceStack extends ChangeNotifier {
  TempoSourceStack([Iterable<TempoSource> sources = const []]) {
    for (final source in sources) {
      _sources.add(source);
      source.addListener(notifyListeners);
    }
  }

  final List<TempoSource> _sources = [];

  /// The sources in this stack, in insertion order. A detached snapshot.
  List<TempoSource> get sources => List.unmodifiable(_sources);

  /// Smallest tempo [apply] will hand back, so a hard-down bend can never drive
  /// the clock to zero or negative BPM.
  static const double _minTempo = 1;

  /// Add [source] to the stack and start tracking its notifications. Notifies
  /// listeners, since a new source may already be modulating.
  void add(TempoSource source) {
    _sources.add(source);
    source.addListener(notifyListeners);
    notifyListeners();
  }

  /// Remove [source] by identity and stop tracking it. Returns `true` if it was
  /// present. Notifies listeners when a removal actually changed the stack.
  bool remove(TempoSource source) {
    if (!_sources.remove(source)) return false;
    source.removeListener(notifyListeners);
    notifyListeners();
    return true;
  }

  /// The summed BPM offset of every *modulating* source; `0` when all rest.
  /// Idle sources are skipped, so a resting fader in the list contributes
  /// nothing.
  double get offset {
    var sum = 0.0;
    for (final source in _sources) {
      if (source.isModulating) sum += source.offset;
    }
    return sum;
  }

  /// Whether any source is currently modulating — the zero-idle-cost gate. When
  /// `false` the seam adds nothing to the base tempo and the player can skip the
  /// bend path entirely.
  bool get isModulating => _sources.any((source) => source.isModulating);

  /// [baseTempo] bent by the summed [offset], floored at [_minTempo]. Returns
  /// [baseTempo] unchanged when nothing modulates, so an unbent domain plays
  /// exactly its base rate (no clamp artefacts, no needless recompute).
  double apply(double baseTempo) {
    if (!isModulating) return baseTempo;
    final bent = baseTempo + offset;
    return bent < _minTempo ? _minTempo : bent;
  }

  @override
  void dispose() {
    for (final source in _sources) {
      source.removeListener(notifyListeners);
    }
    _sources.clear();
    super.dispose();
  }
}
