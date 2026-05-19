import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'patch_node_id.dart';
import 'patch_port.dart';

/// One placeable, draggable object on the patcher canvas.
///
/// Owns the mutable canvas-side state for one native patcher object:
/// position (live during drags) and the armed flag (display-only glow).
/// Listeners are notified on these changes only — graph-level changes
/// (creation, deletion, cables) fire on [PatchGraph] instead.
class PatchNode extends ChangeNotifier {
  PatchNode({
    required this.id,
    required this.type,
    required this.title,
    required this.voice,
    required Offset position,
    required this.size,
    required this.inputs,
    required this.outputs,
  }) : _position = position;

  /// Stable id mirroring the native `PHandle.id`.
  final PatchNodeId id;

  /// Object type identifier — one of the `Obj.*` constants from
  /// `package:yse` (e.g. `'~sine'`, `'.slider'`).
  final String type;

  /// Display title shown in the node header. Uppercase mono.
  final String title;

  /// Voice swatch index in `[1, 6]`.
  final int voice;

  /// On-canvas size in logical pixels.
  final Size size;

  /// Inlet topology, ordered by [PatchPort.index].
  final List<PatchPort> inputs;

  /// Outlet topology, ordered by [PatchPort.index].
  final List<PatchPort> outputs;

  Offset _position;
  bool _armed = false;

  /// Top-left position in canvas-local coordinates.
  Offset get position => _position;

  /// Whether the node draws its voiced glow border. Display-only.
  bool get armed => _armed;

  /// Move the node to [position]. Idempotent — does not notify if
  /// the position is unchanged.
  void moveTo(Offset position) {
    if (_position == position) return;
    _position = position;
    notifyListeners();
  }

  /// Toggle the armed/glow state.
  void setArmed(bool value) {
    if (_armed == value) return;
    _armed = value;
    notifyListeners();
  }
}
