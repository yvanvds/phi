import 'package:flutter/foundation.dart';

/// A control-rate contributor to a played domain's tempo (issue #104).
///
/// Tempo is *played, not set* (`docs/timing-architecture.md` §3): a domain's
/// tempo is a base rate plus the sum of its sources' [offset]s, evaluated in
/// Dart at control rate. The engine primitive stays dumb (`setTempo`);
/// expressiveness lives here. The list of sources will almost always hold a
/// single entry — but modelling the input as a summed stack now costs nothing
/// and lets future sources (state-machine ramps, LFO-on-time, spatial coupling,
/// a convergence autopilot) compose behind the same seam without ever touching
/// the engine.
///
/// A source is a [Listenable] so the seam ([TempoSourceStack]) can re-derive the
/// summed tempo the instant a source moves. Pure Dart — no engine wiring; a
/// source produces a number, nothing more.
abstract class TempoSource implements Listenable {
  /// The BPM offset this source adds to the base tempo right now. Positive
  /// speeds the domain up, negative slows it; summed with every other source.
  /// A resting source returns `0`.
  double get offset;

  /// Whether this source is currently bending the tempo. `false` means its
  /// [offset] rests at zero and the seam can skip it entirely — the zero-idle-
  /// cost property: when *every* source is idle the stack adds nothing and needs
  /// no per-frame work or FFI. A source that will one day animate (an LFO, a
  /// ramp) flips this `true` only while it actually moves, which is the hook a
  /// future control-rate ticker engages on.
  bool get isModulating;
}
