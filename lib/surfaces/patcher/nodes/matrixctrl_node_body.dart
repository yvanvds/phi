import 'package:flutter/widgets.dart';

import '../../../design/widgets/patcher/patch_matrix_grid.dart';
import '../../../domain/patcher/matrix_gesture.dart';
import '../../../domain/patcher/matrixctrl_args.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../domain/patcher/slider_range.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';

/// Body for the `.matrixctrl` node — a live [PatchMatrixGrid], one cell per
/// cell of the object's grid (issue #474).
///
/// The grid is the GUI value read **per cell** (`GuiValueRead.cells`), from the
/// controller's cache of the poll's read, so a cable-driven change repaints
/// without parsing a whole-grid string (over 100 KB at 256 × 256). Its shape
/// and range come from the creation arguments ([MatrixctrlArgs]), which is
/// also how the engine shapes it.
///
/// **Editing** ([MatrixGesture]): a click toggles a cell between its minimum
/// and maximum, a drag paints that value across the cells it crosses, and on
/// a stepped grid (a maximum above 1) a vertical drag on one cell steps it.
/// Each cell is written with the protocol's `set <index> <value>`
/// ([PatcherController.setGuiValueCell]), which the object stores and answers
/// with `<column> <row> <value>` on outlet 0 — ready for `.matrix` or
/// `.router`. While the pointer is down, inbound values are ignored, as on the
/// `.multislider`; release re-reads the grid once.
class MatrixctrlNodeBody extends StatefulWidget {
  const MatrixctrlNodeBody({
    required this.node,
    required this.controller,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  @override
  State<MatrixctrlNodeBody> createState() => _MatrixctrlNodeBodyState();
}

class _MatrixctrlNodeBodyState extends State<MatrixctrlNodeBody> {
  late final GuiValueLink _gui;

  /// Each cell in the object's own units, column-major.
  late List<double> _values;

  MatrixGesture? _gesture;

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
  void didUpdateWidget(MatrixctrlNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gui.rebind(widget.node);
  }

  @override
  void dispose() {
    _gui.dispose();
    super.dispose();
  }

  MatrixctrlArgs get _args =>
      MatrixctrlArgs.parse(widget.controller.argsOf(widget.node.id));

  void _read() {
    final low = _args.range.low;
    _values = [
      for (final cell in widget.controller.guiValueCellsOf(widget.node.id))
        double.tryParse(cell) ?? low,
    ];
  }

  void _follow() {
    if (_gesture != null) return;
    setState(_read);
  }

  void _write(Map<int, double> cells) {
    if (cells.isEmpty) return;
    final next = [..._values];
    for (final MapEntry(key: i, value: v) in cells.entries) {
      if (i >= next.length) continue;
      next[i] = v;
      widget.controller.setGuiValueCell(
        widget.node.id,
        i,
        SliderRange.format(v),
      );
    }
    setState(() => _values = next);
  }

  void _down(Offset local, Size size) {
    if (size.isEmpty) return;
    final gesture = _gesture = MatrixGesture(
      args: _args,
      width: size.width,
      height: size.height,
    );
    final (column, row) = gesture.cellAt(local.dx, local.dy);
    final index = gesture.args.indexOf(column, row);
    final current = index < _values.length
        ? _values[index]
        : gesture.args.range.low;
    _write(gesture.down(local.dx, local.dy, current));
  }

  void _move(Offset local) {
    final gesture = _gesture;
    if (gesture == null) return;
    _write(gesture.moveTo(local.dx, local.dy));
  }

  void _up() {
    final gesture = _gesture;
    if (gesture == null) return;
    _write(gesture.up());
    _end();
  }

  void _end() {
    if (_gesture == null) return;
    _gesture = null;
    setState(_read);
  }

  @override
  Widget build(BuildContext context) {
    final args = _args;
    final range = args.range;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => _down(d.localPosition, size),
          onPanUpdate: (d) => _move(d.localPosition),
          onPanEnd: (_) => _up(),
          // A press lifted before it travels far enough to be a drag ends as a
          // cancel: that is a click, so it finishes like a lift.
          onPanCancel: _up,
          child: PatchMatrixGrid(
            columns: args.columns,
            rows: args.rows,
            values: [for (final v in _values) range.positionOf(v)],
            voice: widget.node.voice,
          ),
        );
      },
    );
  }
}
