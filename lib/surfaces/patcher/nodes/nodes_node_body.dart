import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../design/widgets/patcher/patch_nodes_field.dart';
import '../../../domain/patcher/field_node.dart';
import '../../../domain/patcher/nodes_edit.dart';
import '../../../domain/patcher/nodes_edit_kind.dart';
import '../../../domain/patcher/nodes_field.dart';
import '../../../domain/patcher/nodes_gesture.dart';
import '../../../domain/patcher/nodes_view.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../domain/patcher/slider_range.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';

/// Body for the `.nodes` node — a live [PatchNodesField], the interpolation
/// pad that blends between circular nodes (issue #476).
///
/// The nodes are the GUI value read **per cell** (`GuiValueRead.cells`), one
/// `<x> <y> <radius>` cell per node, so a cable-driven field — a whole-field
/// list, a `set`, a `.preset` recall — redraws, and the node count follows the
/// live cell count rather than the `count` argument.
///
/// **In run mode** ([NodesGesture]):
///
/// - a press or drag puts the cursor under the pointer and sends it as
///   `<x> <y>` on the hot inlet; the object answers with each node's distance
///   on outlet 1 and its weight on outlet 0;
/// - an Alt-drag on a node moves it (`set <i> <x> <y>`, the protocol's cell
///   write, which keeps its radius), and an Alt-drag on its rim resizes it
///   (`set <i> <x> <y> <radius>`).
///
/// Layout editing lives in run mode, behind Alt as `.function`'s bend does,
/// because edit mode's presses belong to the canvas (moving the box). Every
/// write lands in the object, which holds the field; the body keeps only the
/// cursor, which no read reports, and shades each node by the weight
/// [NodesField] computes for it — the same sum the object sends. A cursor
/// driven over a cable is not seen. Like every run-mode performance value the
/// writes are not journaled. While the pointer is down, inbound values are
/// ignored; each write re-reads the field (asking again, issue #514), and
/// release re-reads it once more.
class NodesNodeBody extends StatefulWidget {
  const NodesNodeBody({
    required this.node,
    required this.controller,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  @override
  State<NodesNodeBody> createState() => _NodesNodeBodyState();
}

class _NodesNodeBodyState extends State<NodesNodeBody> {
  late final GuiValueLink _gui;
  late List<FieldNode> _nodes;

  /// Where the cursor is — the engine's starting origin until a press moves
  /// it.
  (double, double) _cursor = (0, 0);

  NodesGesture? _gesture;
  int? _selected;

  @override
  void initState() {
    super.initState();
    _gui = GuiValueLink(
      node: widget.node,
      controller: widget.controller,
      onInbound: (_) => _follow(),
    );
    _read();
  }

  @override
  void didUpdateWidget(NodesNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gui.rebind(widget.node);
  }

  @override
  void dispose() {
    _gui.dispose();
    super.dispose();
  }

  void _read() {
    _nodes = [
      for (final cell in widget.controller.guiValueCellsOf(widget.node.id))
        ?FieldNode.parse(cell),
    ];
  }

  void _follow() {
    if (_gesture != null) return;
    setState(_read);
  }

  /// Send [edit] to the object, then read the field back.
  void _send(NodesEdit edit) {
    final id = widget.node.id;
    final controller = widget.controller;
    String n(double v) => SliderRange.format(v);
    switch (edit.kind) {
      case NodesEditKind.cursor:
        _cursor = (edit.x, edit.y);
        controller.setControlList(
          id,
          inlet: 0,
          list: '${n(edit.x)} ${n(edit.y)}',
        );
      case NodesEditKind.move:
        controller.setGuiValueCell(id, edit.index, '${n(edit.x)} ${n(edit.y)}');
      case NodesEditKind.resize:
        controller.setGuiValueCell(
          id,
          edit.index,
          '${n(edit.x)} ${n(edit.y)} ${n(edit.radius)}',
        );
    }
    _read();
  }

  void _down(PointerDownEvent event, Size size) {
    if (event.buttons != kPrimaryButton) return;
    final gesture = _gesture = NodesGesture(
      view: NodesView(width: size.width, height: size.height),
      nodes: _nodes,
    );
    final edit = gesture.down(
      event.localPosition.dx,
      event.localPosition.dy,
      alt: HardwareKeyboard.instance.isAltPressed,
    );
    setState(() {
      if (edit != null) _send(edit);
      _selected = gesture.selected;
    });
  }

  void _move(PointerMoveEvent event) {
    final gesture = _gesture;
    if (gesture == null) return;
    final edit = gesture.moveTo(event.localPosition.dx, event.localPosition.dy);
    if (edit == null) return;
    setState(() => _send(edit));
  }

  void _up() {
    final gesture = _gesture;
    if (gesture == null) return;
    gesture.up();
    _gesture = null;
    setState(() {
      _selected = null;
      _read();
    });
  }

  @override
  Widget build(BuildContext context) {
    final (cx, cy) = _cursor;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _down(e, size),
          onPointerMove: _move,
          onPointerUp: (_) => _up(),
          onPointerCancel: (_) => _up(),
          child: PatchNodesField(
            nodes: _nodes,
            weights: NodesField.weights(_nodes, cx, cy),
            cursor: _cursor,
            selected: _selected,
            voice: widget.node.voice,
          ),
        );
      },
    );
  }
}
