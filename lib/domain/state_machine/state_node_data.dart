import 'dart:ui';

import '../project/entity_address.dart';

/// One state node as the canvas renders it — the immutable, address-keyed
/// view row the registry-backed `StateMachineController` derives from a
/// `state.` entity (design `docs/design/state-graph.md` §3, issue #241).
///
/// Replaces the mutable `PerformanceState` of the pre-registry scaffold: the
/// registry (plus the controller's transient drag state) is the source of
/// truth now, so the node model is a plain value the controller rebuilds on
/// every change rather than a listenable object of its own.
class StateNodeData {
  const StateNodeData({
    required this.address,
    required this.voice,
    required this.position,
  });

  /// The `state.` entity this node renders.
  final EntityAddress address;

  /// Voice accent for the corner pins. States carry no persisted voice —
  /// the controller assigns one from the node's registry order, purely
  /// cosmetic.
  final int voice;

  /// Top-left position in canvas-local coordinates — the persisted payload
  /// position, or the in-flight drag position while the node is dragged.
  final Offset position;

  /// The display name shown in the node header — the address leaf, the
  /// same one-name identity clips use (issue #184).
  String get name => address.name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StateNodeData &&
          other.address == address &&
          other.voice == voice &&
          other.position == position;

  @override
  int get hashCode => Object.hash(address, voice, position);

  @override
  String toString() => 'StateNodeData($address @ $position, voice $voice)';
}
