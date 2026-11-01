import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../design/widgets/patcher/patch_function_graph.dart';
import '../../../domain/patcher/function_args.dart';
import '../../../domain/patcher/function_edit.dart';
import '../../../domain/patcher/function_edit_kind.dart';
import '../../../domain/patcher/function_gesture.dart';
import '../../../domain/patcher/function_point.dart';
import '../../../domain/patcher/function_view.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../domain/patcher/slider_range.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';

/// Body for the `.function` node — a live [PatchFunctionGraph], the
/// breakpoint editor for the object's envelope (issue #475).
///
/// The points are the GUI value read **per cell** (`GuiValueRead.cells`), one
/// `<x> <y> <curve>` cell per point in ascending-x order, so a cable-driven
/// change redraws. The y axis is the creation arguments' `minimum maximum`
/// ([FunctionArgs]) and the x axis the domain the points span
/// ([FunctionView]).
///
/// **Editing** ([FunctionGesture]), in run mode:
///
/// - a press on empty space adds a point (`<x> <y>`), and the same drag then
///   moves it;
/// - a drag on a point moves it (`set <i> <x> <y>`, the protocol's cell
///   write, which keeps its curve);
/// - an Alt-drag on a segment bends it (`setcurve <i> <c>`);
/// - a double-click on a point, or Delete with one taken, removes it
///   (`clear <i>`).
///
/// Every write lands in the object, which holds the points and saves them
/// with the patch, so the editor keeps no state of its own beyond the point it
/// has taken. Edits are silent on the object's outlets — the ramp list goes
/// out on a bang — and, like every run-mode performance value, they are not
/// journaled. While the pointer is down, inbound values are ignored; each
/// write re-reads the points (asking again, issue #514), and release re-reads
/// them once more.
class FunctionNodeBody extends StatefulWidget {
  const FunctionNodeBody({
    required this.node,
    required this.controller,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  @override
  State<FunctionNodeBody> createState() => _FunctionNodeBodyState();
}

class _FunctionNodeBodyState extends State<FunctionNodeBody> {
  late final GuiValueLink _gui;
  final FocusNode _focus = FocusNode(debugLabel: 'function-body');

  late List<FunctionPoint> _points;

  FunctionGesture? _gesture;
  int? _selected;

  /// The point the press before last took, and the one the last press took —
  /// a double-click removes a point only when both clicks landed on it.
  int? _previousHit;
  int? _lastHit;

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
  void didUpdateWidget(FunctionNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gui.rebind(widget.node);
  }

  @override
  void dispose() {
    _gui.dispose();
    _focus.dispose();
    super.dispose();
  }

  FunctionArgs get _args =>
      FunctionArgs.parse(widget.controller.argsOf(widget.node.id));

  void _read() {
    _points = [
      for (final cell in widget.controller.guiValueCellsOf(widget.node.id))
        ?FunctionPoint.parse(cell),
    ];
    final selected = _selected;
    if (selected != null && selected >= _points.length) _selected = null;
  }

  void _follow() {
    if (_gesture != null) return;
    setState(_read);
  }

  FunctionView _view(Size size) => FunctionView(
    points: _points,
    range: _args.range,
    width: size.width - 2 * PatchFunctionGraph.inset,
    height: size.height - 2 * PatchFunctionGraph.inset,
  );

  (double, double) _plot(Offset local) => (
    local.dx - PatchFunctionGraph.inset,
    local.dy - PatchFunctionGraph.inset,
  );

  /// Send [edit] to the object, then read the points back.
  void _send(FunctionEdit edit) {
    final id = widget.node.id;
    final controller = widget.controller;
    String n(double v) => SliderRange.format(v);
    switch (edit.kind) {
      case FunctionEditKind.add:
        controller.setControlList(
          id,
          inlet: 0,
          list: '${n(edit.x)} ${n(edit.y)}',
        );
      case FunctionEditKind.move:
        controller.setGuiValueCell(id, edit.index, '${n(edit.x)} ${n(edit.y)}');
      case FunctionEditKind.curve:
        controller.sendControlMessage(
          id,
          inlet: 0,
          message: 'setcurve ${edit.index} ${n(edit.curve)}',
        );
      case FunctionEditKind.remove:
        controller.sendControlMessage(
          id,
          inlet: 0,
          message: 'clear ${edit.index}',
        );
    }
    _read();
  }

  void _down(PointerDownEvent event, Size size) {
    if (event.buttons != kPrimaryButton) return;
    final view = _view(size);
    final gesture = _gesture = FunctionGesture(view: view, args: _args);
    final (px, py) = _plot(event.localPosition);
    final add = gesture.down(
      px,
      py,
      alt: HardwareKeyboard.instance.isAltPressed,
    );
    _previousHit = _lastHit;
    _lastHit = gesture.pressedPoint ? gesture.selected : null;
    if (add != null) {
      _send(add);
      gesture.adopt(_points, FunctionGesture.indexOfX(_points, add.x));
    }
    setState(() => _selected = gesture.selected);
  }

  void _move(PointerMoveEvent event) {
    final gesture = _gesture;
    if (gesture == null) return;
    final (px, py) = _plot(event.localPosition);
    final edit = gesture.moveTo(px, py);
    if (edit == null) return;
    // A press that drags is no half of a double-click.
    _lastHit = null;
    setState(() => _send(edit));
  }

  void _up({bool lifted = true}) {
    final gesture = _gesture;
    if (gesture == null) return;
    // Taken on release, after the enclosing pane's pointer-down focus grab,
    // so Delete reaches this body; every other key bubbles on to the canvas.
    if (lifted) _focus.requestFocus();
    gesture.up();
    _gesture = null;
    setState(_read);
  }

  void _remove(int index) {
    setState(() {
      _send(FunctionEdit.remove(index));
      _selected = null;
      _previousHit = null;
      _lastHit = null;
    });
  }

  void _doubleTap() {
    final hit = _lastHit;
    if (hit == null || hit != _previousHit) return;
    _remove(hit);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final selected = _selected;
    if (event is! KeyDownEvent || selected == null) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.delete &&
        event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    _remove(selected);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final range = _args.range;
    final view = FunctionView(
      points: _points,
      range: range,
      width: 1,
      height: 1,
    );
    final domain = _gesture?.domain ?? view.domain;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Focus(
          focusNode: _focus,
          onKeyEvent: _key,
          child: GestureDetector(
            onDoubleTap: _doubleTap,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _down(e, size),
              onPointerMove: _move,
              onPointerUp: (_) => _up(),
              onPointerCancel: (_) => _up(lifted: false),
              child: PatchFunctionGraph(
                positions: [
                  for (final p in _points)
                    ((p.x / domain).clamp(0.0, 1.0), range.positionOf(p.y)),
                ],
                curves: [for (final p in _points) p.curve],
                selected: _selected,
                voice: widget.node.voice,
              ),
            ),
          ),
        );
      },
    );
  }
}
