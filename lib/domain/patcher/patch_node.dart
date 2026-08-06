import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'patch_node_id.dart';
import 'patch_port.dart';

/// One placeable, draggable object on the patcher canvas.
///
/// Owns the mutable canvas-side state for one native patcher object:
/// position (live during drags), the armed flag (display-only glow), and the
/// port topology, which a params change can reshape ([reshapePorts]).
/// Listeners are notified on these changes only — graph-level changes
/// (creation, deletion, cables) fire on [PatchGraph] instead — plus the
/// [markParamsChanged] signal for state the node does *not* own.
class PatchNode extends ChangeNotifier {
  PatchNode({
    required this.id,
    required this.type,
    required this.voice,
    required this._position,
    required this._size,
    required this._inputs,
    required this._outputs,
  });

  /// Stable id mirroring the native `PHandle.id`.
  final PatchNodeId id;

  /// Object type identifier — one of the `Obj.*` constants from
  /// `package:yse` (e.g. `'~sine'`, `'.slider'`).
  ///
  /// The only name a node carries. There used to be a display `title` beside it
  /// for the node header to print; with no headers anywhere (issues #379, #381)
  /// nothing rendered it, so it went rather than lingering dead (design §7).
  final String type;

  /// Voice swatch index in `[1, 6]`.
  final int voice;

  Offset _position;
  Size _size;
  List<PatchPort> _inputs;
  List<PatchPort> _outputs;
  bool _armed = false;
  int _guiRevision = 0;

  /// Top-left position in canvas-local coordinates.
  Offset get position => _position;

  /// On-canvas size in logical pixels.
  Size get size => _size;

  /// Inlet topology, ordered by [PatchPort.index].
  List<PatchPort> get inputs => _inputs;

  /// Outlet topology, ordered by [PatchPort.index].
  List<PatchPort> get outputs => _outputs;

  /// Whether the node draws its voiced glow border. Display-only.
  bool get armed => _armed;

  /// Counts the times the engine has reported a **different** display value
  /// (`guiValue`) for this object — bumped by [markGuiValueChanged].
  ///
  /// A node notifies for several reasons (it moved, it was re-shaped, its
  /// params changed); a live GUI body caches the revision it last reconciled
  /// against so it can tell *this* one from the rest and re-read the engine
  /// only when there is genuinely a new value to read (issue #357).
  int get guiRevision => _guiRevision;

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

  /// Re-shape the node to a new port topology (and the box that seats it) —
  /// what the controller applies after re-inspecting a native object whose
  /// creation arguments changed its inlet/outlet count (issue #356).
  ///
  /// The native side decides how many ports an object has from its arguments,
  /// so a `setParams` can reshape the very object the canvas is drawing. Only
  /// the controller calls this, and only with a topology it just read back from
  /// the engine — the mirror never invents ports. Notifies, so the canvas
  /// re-lays-out the node and repaints its cables against the new port
  /// positions.
  void reshapePorts({
    required List<PatchPort> inputs,
    required List<PatchPort> outputs,
    required Size size,
  }) {
    _inputs = inputs;
    _outputs = outputs;
    _size = size;
    notifyListeners();
  }

  /// Announce that the object's creation arguments changed, so a body that
  /// renders them repaints (issue #354).
  ///
  /// The argument string itself lives on the controller, which owns the native
  /// handle it was written to — the node only carries the *signal*, because the
  /// canvas listens per node. Raised by `PatcherController.setNodeParams`, which
  /// every params-dialog apply and its undo/redo run through.
  void markParamsChanged() => notifyListeners();

  /// Announce that the engine now reports a **different** `guiValue` for this
  /// object, so the body that displays it repaints (issue #357).
  ///
  /// The value itself lives on the native object; the node only carries the
  /// signal, exactly as [markParamsChanged] does — the canvas listens per node,
  /// and a body re-reads through `PatcherController.guiValueOf`. Raised by
  /// `PatcherController.refreshGuiValues`, the gated poll the patcher surface
  /// runs while it is on screen, which is what makes a value arriving over a
  /// *cable* visible at all: nothing else on the Dart side ever hears about it.
  void markGuiValueChanged() {
    _guiRevision++;
    notifyListeners();
  }
}
