import 'package:vector_math/vector_math_64.dart';

/// A region of scene space that acts on the agents currently inside it.
///
/// Vision §3.3: *"A volume in space can act as an effects send."* An
/// [EffectVolume] pairs a shape — its [contains] test — with the effect it
/// applies: a named [effect] the DSP layer will later route to, and a [send]
/// amount (0..1) describing how strongly agents inside are fed into it. The
/// [SceneField] recomputes membership every step, so an agent picks up (and
/// drops) a volume's send as it drifts across the boundary.
///
/// Pure-Dart and immutable. The shape lives in the concrete subclasses
/// ([SphereVolume], AABB [BoxVolume]); this base owns only the effect payload
/// and the membership contract. Placement is programmatic for now (construct
/// and add to the field); direct-manipulation placement is a later slice.
///
/// This is a *send*, not a force: it surfaces a tag for the engine bridge to
/// consume, and never touches an agent's velocity. Scatter (#81) and grab
/// (#82) are the force-like machinery that will modify motion.
abstract class EffectVolume {
  const EffectVolume({required this.effect, required this.send})
    : assert(send >= 0, 'send amount cannot be negative');

  /// The DSP effect this volume routes into — an opaque tag the engine bridge
  /// will resolve to a real effect send in a later slice.
  final String effect;

  /// How strongly agents inside are fed into [effect], nominally 0..1. Left
  /// unclamped at the top so overlapping regions can be summed or scaled by
  /// the DSP layer as it sees fit.
  final double send;

  /// Whether [position] lies within this volume. Boundary points count as
  /// inside, so an agent sitting exactly on the surface is a member.
  bool contains(Vector3 position);
}
