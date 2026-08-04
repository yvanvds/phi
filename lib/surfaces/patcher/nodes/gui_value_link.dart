import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';

/// Keeps one live GUI body in step with the engine's display value for its
/// object (issue #357).
///
/// A body that shows a `guiValue` also holds its own copy of it — a fader
/// position, a toggle's on/off, the text in a number field — because the value
/// has to react to the user's gesture before the engine has been asked about
/// it. That copy is what goes stale when a *cable* drives the object: the
/// native side moves and nothing on the Dart side hears.
///
/// This is the ear. The body constructs one in `initState` and [dispose]s it;
/// it listens to the [PatchNode] and calls `onInbound` with the engine's fresh
/// value each time [PatchNode.guiRevision] moves — the wake-up
/// `PatcherController.refreshGuiValues` raises, and only that. A node also
/// notifies when it is dragged, re-shaped, or has its params applied; those are
/// filtered out here so no body re-reads the engine over a move.
///
/// The callback is a *report*, not a command: a body mid-gesture (a thumb under
/// the pointer, a number field being typed into) is free to drop the value it
/// is handed rather than let the poll yank the control out of the user's hand.
class GuiValueLink {
  GuiValueLink({
    required PatchNode node,
    required PatcherController controller,
    required void Function(String value) onInbound,
  }) : _node = node,
       _controller = controller,
       _onInbound = onInbound,
       _revision = node.guiRevision {
    _node.addListener(_onNodeChanged);
  }

  PatchNode _node;
  final PatcherController _controller;
  final void Function(String value) _onInbound;
  int _revision;

  /// The engine's current display value for the bound node — what a body seeds
  /// from and what it snaps back to when an edit is abandoned.
  String get value => _controller.guiValueOf(_node.id);

  /// Follow the body's widget onto a different [node].
  ///
  /// The canvas builds node views positionally, so a deletion can hand a body's
  /// State a *different* node; without this the link would keep listening to
  /// the old one and leak a subscription onto it. Re-binding reports the new
  /// object's value straight away, since it is a wholly new thing to display.
  void rebind(PatchNode node) {
    if (identical(node, _node)) return;
    _node.removeListener(_onNodeChanged);
    _node = node;
    _revision = node.guiRevision;
    _node.addListener(_onNodeChanged);
    _onInbound(value);
  }

  void dispose() => _node.removeListener(_onNodeChanged);

  void _onNodeChanged() {
    if (_node.guiRevision == _revision) return;
    _revision = _node.guiRevision;
    _onInbound(value);
  }
}
