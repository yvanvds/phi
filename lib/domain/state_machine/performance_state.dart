import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'performance_state_id.dart';

/// One node in the state graph — a single performance state.
///
/// Owns the canvas-side mutable bits (position, name) for one state.
/// Listeners are notified on these changes only; graph-level changes
/// (creation, deletion, transitions) fire on [StateGraph] instead.
/// Mirrors the [PatchNode] / [PatchGraph] split.
class PerformanceState extends ChangeNotifier {
  PerformanceState({
    required this.id,
    required String name,
    required this.voice,
    required Offset position,
  }) : _name = name,
       _position = position;

  final PerformanceStateId id;
  final int voice;

  String _name;
  Offset _position;

  /// Display name shown in the node header.
  String get name => _name;

  /// Top-left position in canvas-local coordinates.
  Offset get position => _position;

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
}
