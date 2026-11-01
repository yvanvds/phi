import 'package:flutter/widgets.dart';

import '../../../design/widgets/patcher/patch_keyboard.dart';
import '../../../domain/midi/midi_pitch.dart';
import '../../../domain/patcher/keyboard_gesture.dart';
import '../../../domain/patcher/keyboard_layout.dart';
import '../../../domain/patcher/patch_gui_property.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';

/// Body for the `.kslider` node — a live [PatchKeyboard] (issue #473).
///
/// The object's GUI value is 128 cells, the velocity held on each key, read
/// **per cell** (`GuiValueRead.cells`) and only across the keys the keyboard
/// shows ([PatcherController.setGuiCellWindow]) — the visible range is the
/// node's [PatchGuiProperty.keyLow] / [PatchGuiProperty.keyHigh] decoration,
/// not engine state. Every held key lights from those cells, so notes played
/// into the object down a cable show as well as the ones pressed here.
///
/// **Playing**: a press plays the key under the pointer, louder the lower down
/// the key it lands (or at the node's fixed [PatchGuiProperty.keyVelocity]),
/// sliding onto another key releases the first and plays the next
/// ([KeyboardGesture]), and lifting releases it. Each note goes in as the
/// protocol's `set <pitch> <velocity>` ([PatcherController.setGuiValueCell]),
/// which the object plays: velocity out of outlet 1, then pitch out of outlet
/// 0, so it pairs with a `.makenote` or `.noteon` downstream. Velocity 0 is the
/// release. Going through `set` rather than a `<pitch> <velocity>` list keeps
/// the object's own stored `velocity` untouched.
class KsliderNodeBody extends StatefulWidget {
  const KsliderNodeBody({
    required this.node,
    required this.controller,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  @override
  State<KsliderNodeBody> createState() => _KsliderNodeBodyState();
}

class _KsliderNodeBodyState extends State<KsliderNodeBody> {
  late final GuiValueLink _gui;
  late KeyboardLayout _layout;
  Map<int, int> _held = const {};

  final KeyboardGesture _gesture = KeyboardGesture();

  @override
  void initState() {
    super.initState();
    _gui = GuiValueLink(
      node: widget.node,
      controller: widget.controller,
      onInbound: (_) => setState(_read),
    );
    _layout = _layoutFromGui();
    _window();
    _read();
  }

  @override
  void didUpdateWidget(KsliderNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final layout = _layoutFromGui();
    if (layout.low != _layout.low ||
        layout.high != _layout.high ||
        !identical(oldWidget.node, widget.node)) {
      _layout = layout;
      _window();
    }
    _gui.rebind(widget.node);
    _read();
  }

  @override
  void dispose() {
    _send(_gesture.release());
    _gui.dispose();
    super.dispose();
  }

  KeyboardLayout _layoutFromGui() => KeyboardLayout.fromGui(
    widget.controller.guiPropertyOf(widget.node.id, PatchGuiProperty.keyLow),
    widget.controller.guiPropertyOf(widget.node.id, PatchGuiProperty.keyHigh),
  );

  /// Poll only the keys on show.
  void _window() => widget.controller.setGuiCellWindow(
    widget.node.id,
    start: _layout.low,
    end: _layout.high + 1,
  );

  void _read() {
    final cells = widget.controller.guiValueCellsOf(widget.node.id);
    _held = {
      for (final pitch in _layout.pitches)
        if (pitch < cells.length)
          if (int.tryParse(cells[pitch]) case final v? when v > 0) pitch: v,
    };
  }

  /// The fixed press velocity stored on the node, or null to play by depth.
  int? get _fixedVelocity {
    final stored = int.tryParse(
      widget.controller.guiPropertyOf(
        widget.node.id,
        PatchGuiProperty.keyVelocity,
      ),
    );
    if (stored == null || stored < 1) return null;
    return stored > MidiPitch.maxVelocity ? MidiPitch.maxVelocity : stored;
  }

  void _send(List<({int pitch, int velocity})> notes) {
    for (final note in notes) {
      widget.controller.setGuiValueCell(
        widget.node.id,
        note.pitch,
        '${note.velocity}',
      );
    }
  }

  void _pointer(Offset local, Size size) {
    if (size.isEmpty) return;
    final x = local.dx / size.width;
    final y = local.dy / size.height;
    final pitch = _layout.keyAt(x, y);
    final velocity = pitch == null
        ? 0
        : _fixedVelocity ?? _layout.velocityAt(pitch, y);
    final notes = _gesture.moveTo(pitch, velocity);
    if (notes.isEmpty) return;
    _send(notes);
    setState(_read);
  }

  void _release() {
    final notes = _gesture.release();
    if (notes.isEmpty) return;
    _send(notes);
    setState(_read);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => _pointer(d.localPosition, size),
          onPanUpdate: (d) => _pointer(d.localPosition, size),
          onPanEnd: (_) => _release(),
          onPanCancel: _release,
          child: PatchKeyboard(
            layout: _layout,
            held: _held,
            voice: widget.node.voice,
          ),
        );
      },
    );
  }
}
