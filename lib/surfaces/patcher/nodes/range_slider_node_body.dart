import 'package:flutter/widgets.dart';

import '../../../design/widgets/patcher/patch_range_bar.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../domain/patcher/range_slider_gesture.dart';
import '../../../domain/patcher/slider_range.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';

/// Body for the `.rslider` node — a live [PatchRangeBar] holding the object's
/// two ends (issue #472).
///
/// The object's GUI value is two cells, low and high, in its own units inside
/// `minimum maximum` ([SliderRange], read from the creation arguments each
/// build). The body reads them per cell through the controller's cache — the
/// read the poll already made, never a second one — and draws them as
/// positions along the bar.
///
/// **Dragging** follows [RangeSliderGesture]: grab an end to move it, or the
/// middle to slide the whole range. Each move sends both ends as one list on
/// the hot inlet ([PatcherController.setControlList]), which the object stores
/// and sends on. Like the `.slider`, the bar is upright (low at the bottom),
/// follows cable-driven values through a [GuiValueLink] except while the
/// pointer has hold of it, and re-reads the object once on release.
class RangeSliderNodeBody extends StatefulWidget {
  const RangeSliderNodeBody({
    required this.node,
    required this.controller,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  @override
  State<RangeSliderNodeBody> createState() => _RangeSliderNodeBodyState();
}

class _RangeSliderNodeBodyState extends State<RangeSliderNodeBody> {
  /// Pixels either side of an end that still take hold of it.
  static const double _grabPixels = 6;

  late final GuiValueLink _gui;
  late double _low;
  late double _high;

  RangeSliderGesture? _gesture;

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
  void didUpdateWidget(RangeSliderNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gui.rebind(widget.node);
  }

  @override
  void dispose() {
    _gui.dispose();
    super.dispose();
  }

  SliderRange get _range =>
      SliderRange.fromArgs(widget.controller.argsOf(widget.node.id));

  /// Take the two ends from the controller's cached cells.
  void _read() {
    final cells = widget.controller.guiValueCellsOf(widget.node.id);
    final range = _range;
    double at(int i) => i < cells.length
        ? range.positionOf(double.tryParse(cells[i]) ?? range.low)
        : 0;
    _low = at(0);
    _high = at(1);
  }

  void _follow() {
    if (_gesture != null) return;
    setState(_read);
  }

  double _positionAt(Offset local, double height) =>
      height <= 0 ? 0 : 1 - local.dy / height;

  void _down(Offset local, Size size) {
    final gesture = RangeSliderGesture.start(
      low: _low,
      high: _high,
      at: _positionAt(local, size.height),
      grabRadius: size.height <= 0 ? 0 : _grabPixels / size.height,
    );
    _gesture = gesture;
    _push(gesture);
  }

  void _move(Offset local, Size size) {
    final gesture = _gesture;
    if (gesture == null) return;
    gesture.update(_positionAt(local, size.height));
    _push(gesture);
  }

  void _push(RangeSliderGesture gesture) {
    if (gesture.low == _low && gesture.high == _high && gesture.movesBoth) {
      return;
    }
    setState(() {
      _low = gesture.low;
      _high = gesture.high;
    });
    final range = _range;
    widget.controller.setControlList(
      widget.node.id,
      inlet: 0,
      list:
          '${SliderRange.format(range.valueAt(_low))} '
          '${SliderRange.format(range.valueAt(_high))}',
    );
  }

  /// Hand the bar back to the engine and re-read it once.
  void _release() {
    if (_gesture == null) return;
    _gesture = null;
    setState(_read);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => _down(d.localPosition, size),
          onPanUpdate: (d) => _move(d.localPosition, size),
          onPanEnd: (_) => _release(),
          onPanCancel: _release,
          child: PatchRangeBar(
            low: _low,
            high: _high,
            voice: widget.node.voice,
          ),
        );
      },
    );
  }
}
