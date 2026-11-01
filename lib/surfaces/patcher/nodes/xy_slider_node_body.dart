import 'package:flutter/widgets.dart';

import '../../../design/widgets/patcher/patch_xy_pad.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../domain/patcher/slider_range.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';

/// Body for the `.xyslider` node — a live [PatchXyPad] holding the object's x
/// and y (issue #472).
///
/// The GUI value is two cells, x and y, each in its own units inside
/// `xminimum xmaximum` and `yminimum ymaximum` ([SliderRange], read from the
/// creation arguments each build). The body reads them per cell from the
/// controller's cache.
///
/// **A press or a drag** puts the puck under the pointer and sends both values
/// as one list `x y` on the hot inlet ([PatcherController.setControlList]), so
/// one gesture moves two parameters together. As with the `.slider`, y rises
/// upwards, a cable-driven value moves the puck through a [GuiValueLink]
/// except while the pointer has hold of it, and release re-reads the object.
class XySliderNodeBody extends StatefulWidget {
  const XySliderNodeBody({
    required this.node,
    required this.controller,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  @override
  State<XySliderNodeBody> createState() => _XySliderNodeBodyState();
}

class _XySliderNodeBodyState extends State<XySliderNodeBody> {
  late final GuiValueLink _gui;
  late double _x;
  late double _y;
  bool _held = false;

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
  void didUpdateWidget(XySliderNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gui.rebind(widget.node);
  }

  @override
  void dispose() {
    _gui.dispose();
    super.dispose();
  }

  String get _args => widget.controller.argsOf(widget.node.id);
  SliderRange get _xRange => SliderRange.fromArgs(_args);
  SliderRange get _yRange => SliderRange.fromArgs(_args, at: 2);

  void _read() {
    final cells = widget.controller.guiValueCellsOf(widget.node.id);
    double at(int i, SliderRange range) => i < cells.length
        ? range.positionOf(double.tryParse(cells[i]) ?? range.low)
        : 0;
    _x = at(0, _xRange);
    _y = at(1, _yRange);
  }

  void _follow() {
    if (_held) return;
    setState(_read);
  }

  void _push(Offset local, Size size) {
    if (size.isEmpty) return;
    final x = (local.dx / size.width).clamp(0.0, 1.0);
    final y = (1 - local.dy / size.height).clamp(0.0, 1.0);
    final first = !_held;
    _held = true;
    if (!first && x == _x && y == _y) return;
    setState(() {
      _x = x;
      _y = y;
    });
    widget.controller.setControlList(
      widget.node.id,
      inlet: 0,
      list:
          '${SliderRange.format(_xRange.valueAt(x))} '
          '${SliderRange.format(_yRange.valueAt(y))}',
    );
  }

  void _release() {
    if (!_held) return;
    _held = false;
    setState(_read);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => _push(d.localPosition, size),
          onPanUpdate: (d) => _push(d.localPosition, size),
          onPanEnd: (_) => _release(),
          onPanCancel: _release,
          child: PatchXyPad(x: _x, y: _y, voice: widget.node.voice),
        );
      },
    );
  }
}
