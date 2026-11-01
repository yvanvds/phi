import 'package:flutter/widgets.dart';

import '../../../design/widgets/patcher/patch_slider_bank.dart';
import '../../../domain/patcher/multislider_args.dart';
import '../../../domain/patcher/multislider_stroke.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../domain/patcher/slider_range.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';

/// Body for the `.multislider` node — a live [PatchSliderBank], one bar per
/// cell of the object's bank (issue #472).
///
/// The bank is the GUI value read **per cell** (`GuiValueRead.cells`): the
/// count, then each value, from the controller's cache of the poll's read. The
/// bar count is that live count, not the `size` argument, so a list of another
/// length arriving over a cable re-lays the bars at once. Values are in the
/// object's own units inside `minimum maximum` ([MultisliderArgs]).
///
/// **Drawing**: press and drag across the bank, and each cell the pointer
/// crosses takes the height it passes at ([MultisliderStroke]), written one
/// cell at a time with the protocol's `set <index> <value>`
/// ([PatcherController.setGuiValueCell]) — which the object stores and answers
/// by sending the whole bank. While the pointer draws, inbound values are
/// ignored, as on the `.slider`; release re-reads the bank once.
class MultisliderNodeBody extends StatefulWidget {
  const MultisliderNodeBody({
    required this.node,
    required this.controller,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  @override
  State<MultisliderNodeBody> createState() => _MultisliderNodeBodyState();
}

class _MultisliderNodeBodyState extends State<MultisliderNodeBody> {
  late final GuiValueLink _gui;
  late List<double> _values;

  MultisliderStroke? _stroke;

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
  void didUpdateWidget(MultisliderNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gui.rebind(widget.node);
  }

  @override
  void dispose() {
    _gui.dispose();
    super.dispose();
  }

  MultisliderArgs get _args =>
      MultisliderArgs.parse(widget.controller.argsOf(widget.node.id));

  void _read() {
    final range = _args.range;
    _values = [
      for (final cell in widget.controller.guiValueCellsOf(widget.node.id))
        range.positionOf(double.tryParse(cell) ?? range.low),
    ];
  }

  void _follow() {
    if (_stroke != null) return;
    setState(_read);
  }

  void _draw(Offset local, Size size) {
    if (size.isEmpty || _values.isEmpty) return;
    final stroke = _stroke ??= MultisliderStroke(_values.length);
    final cells = stroke.moveTo(
      local.dx / size.width,
      1 - local.dy / size.height,
    );
    final range = _args.range;
    final next = [..._values];
    for (final MapEntry(key: i, value: v) in cells.entries) {
      if (i >= next.length) continue;
      next[i] = v;
      widget.controller.setGuiValueCell(
        widget.node.id,
        i,
        SliderRange.format(range.valueAt(v)),
      );
    }
    setState(() => _values = next);
  }

  void _release() {
    if (_stroke == null) return;
    _stroke = null;
    setState(_read);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => _draw(d.localPosition, size),
          onPanUpdate: (d) => _draw(d.localPosition, size),
          onPanEnd: (_) => _release(),
          onPanCancel: _release,
          child: PatchSliderBank(values: _values, voice: widget.node.voice),
        );
      },
    );
  }
}
