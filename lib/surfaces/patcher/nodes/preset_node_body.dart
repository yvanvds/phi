import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../design/widgets/patcher/patch_preset_grid.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../domain/patcher/preset_action.dart';
import '../../../domain/patcher/preset_args.dart';
import '../../../domain/patcher/preset_grid.dart';
import '../../../domain/patcher/preset_slots.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';

/// Body for the `.preset` node — a live [PatchPresetGrid], one button per
/// slot of the bank (issue #477).
///
/// **In run mode** a click on a slot recalls it, Shift+click stores the
/// patch's controls into it, and Alt+click clears it ([PresetAction], Max's
/// convention, shown as the grid's tooltip). Each goes out as the message
/// the object takes (`recall 3`, `store 3`, `clear 3`). A recall writes the
/// other controls through their own inlets, and the poll shows their new
/// values the way it shows any cable-driven change.
///
/// The **active** slot is the GUI value (`-1` for none). Which slots are
/// **stored** is not in the GUI value: it is read from what the object saves
/// with the patch ([PatcherController.objectStateOf], a whole-patch dump),
/// so it is asked for on demand: when the body is built, after its own click,
/// and whenever the active slot moves (a store or recall over a cable moves
/// it). A cable-driven `clear` of a slot that is not the active one is
/// therefore seen only at the next of those, until the engine reports
/// occupancy in the GUI value (yvanvds/yse-soundengine#1229). The slots are
/// the object's own state and are saved with the patch. Like every run-mode
/// performance value, the clicks are not journaled.
class PresetNodeBody extends StatefulWidget {
  const PresetNodeBody({
    required this.node,
    required this.controller,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  @override
  State<PresetNodeBody> createState() => _PresetNodeBodyState();
}

class _PresetNodeBodyState extends State<PresetNodeBody> {
  late final GuiValueLink _gui;

  int _active = -1;
  PresetSlots _slots = PresetSlots.empty;

  @override
  void initState() {
    super.initState();
    _gui = GuiValueLink(
      node: widget.node,
      controller: widget.controller,
      onInbound: (_) => setState(_read),
    );
    _read();
  }

  @override
  void didUpdateWidget(PresetNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gui.rebind(widget.node);
  }

  @override
  void dispose() {
    _gui.dispose();
    super.dispose();
  }

  int get _capacity =>
      PresetArgs.parse(widget.controller.argsOf(widget.node.id)).slots;

  void _read() {
    _active = int.tryParse(_gui.value.trim()) ?? -1;
    _slots = PresetSlots.fromState(
      widget.controller.objectStateOf(widget.node.id),
    );
  }

  void _press(PointerDownEvent event, Size size) {
    if (event.buttons != kPrimaryButton) return;
    final slot = PresetGrid(
      slots: _capacity,
      width: size.width,
      height: size.height,
    ).slotAt(event.localPosition.dx, event.localPosition.dy);
    if (slot == null) return;
    final keys = HardwareKeyboard.instance;
    final action = PresetAction.forModifiers(
      shift: keys.isShiftPressed,
      alt: keys.isAltPressed,
    );
    widget.controller.sendControlMessage(
      widget.node.id,
      inlet: 0,
      message: action.messageFor(slot),
    );
    // Asking again after the write (issue #514): the marker and the stored
    // slots as the object now has them.
    setState(_read);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: PresetAction.hint,
      waitDuration: const Duration(milliseconds: 600),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _press(e, size),
            child: PatchPresetGrid(
              slots: _capacity,
              stored: _slots.stored,
              active: _active,
              voice: widget.node.voice,
            ),
          );
        },
      ),
    );
  }
}
