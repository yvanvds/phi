import 'package:flutter/widgets.dart';

import '../../../design/widgets/toggle/phi_toggle.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';

/// Body for the `.t` (toggle) node — a live [PhiToggle] that pushes `1`/`0`
/// into the object's hot inlet via [PatcherController.setControlValue]
/// (`sendFloat`), so flipping it on the canvas drives the graph (design
/// `docs/design/patcher.md` §7).
///
/// The initial on/off state seeds from the object's `guiValue`, so a reopened
/// patch shows the toggle where it was left.
class ToggleNodeBody extends StatefulWidget {
  const ToggleNodeBody({
    required this.node,
    required this.controller,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  @override
  State<ToggleNodeBody> createState() => _ToggleNodeBodyState();
}

class _ToggleNodeBodyState extends State<ToggleNodeBody> {
  late bool _on = _seed();

  bool _seed() {
    final gui = double.tryParse(widget.controller.guiValueOf(widget.node.id));
    return (gui ?? 0) != 0;
  }

  void _flip(bool value) {
    setState(() => _on = value);
    widget.controller.setControlValue(
      widget.node.id,
      inlet: 0,
      value: value ? 1.0 : 0.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: PhiToggle(value: _on, onChanged: _flip),
    );
  }
}
