import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'performance_state_id.dart';
import 'state_snapshot.dart';

/// One node in the state graph — a single performance state.
///
/// Owns the canvas-side mutable bits (position, name, snapshot) for one
/// state. Listeners are notified on these changes only; graph-level
/// changes (creation, deletion, transitions) fire on [StateGraph]
/// instead. Mirrors the [PatchNode] / [PatchGraph] split.
class PerformanceState extends ChangeNotifier {
  PerformanceState({
    required this.id,
    required String name,
    required this.voice,
    required Offset position,
    StateSnapshot snapshot = StateSnapshot.empty,
  }) : _name = name,
       _position = position,
       _snapshot = snapshot;

  final PerformanceStateId id;
  final int voice;

  String _name;
  Offset _position;
  StateSnapshot _snapshot;

  /// Display name shown in the node header.
  String get name => _name;

  /// Top-left position in canvas-local coordinates.
  Offset get position => _position;

  /// What this state captures (domains, code blocks, scene pose). Empty
  /// by default — authoring lands in later phases (#6 / #9 / scene).
  StateSnapshot get snapshot => _snapshot;

  /// Move the node to [position]. Idempotent — does not notify if the
  /// position is unchanged.
  void moveTo(Offset position) {
    if (_position == position) return;
    _position = position;
    notifyListeners();
  }

  /// Rename the state. Idempotent.
  void rename(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == _name) return;
    _name = trimmed;
    notifyListeners();
  }

  /// Replace the snapshot wholesale. Used by future authoring surfaces;
  /// the inspector remains read-only for now.
  void setSnapshot(StateSnapshot snapshot) {
    if (identical(_snapshot, snapshot)) return;
    _snapshot = snapshot;
    notifyListeners();
  }
}
