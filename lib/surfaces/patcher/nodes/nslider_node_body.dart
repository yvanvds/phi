import 'package:flutter/widgets.dart';

import '../../../design/widgets/patcher/patch_staff.dart';
import '../../../domain/midi/midi_pitch.dart';
import '../../../domain/patcher/nslider_args.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../domain/patcher/staff_drag.dart';
import '../../../domain/patcher/staff_note.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';

/// Body for the `.nslider` node — a live [PatchStaff] (issue #473).
///
/// The object's GUI value is two cells, the pitch and how it is spelled (1
/// sharp, -1 flat, 0 natural), read **per cell** (`GuiValueRead.cells`), so a
/// note sent in down a cable — re-spelled or not — shows on the staff.
///
/// **Dragging** vertically moves the pitch a semitone per few pixels, up for
/// higher, inside the object's `minimum maximum` ([StaffDrag]). Each new pitch
/// goes in as an int on the hot inlet, which the object spells its default way
/// (`spelling`) and sends: accidental out of outlet 1, then pitch out of outlet
/// 0. While the pointer holds the note, inbound values are ignored, as on the
/// `.slider`; release re-reads the object once.
class NsliderNodeBody extends StatefulWidget {
  const NsliderNodeBody({
    required this.node,
    required this.controller,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  @override
  State<NsliderNodeBody> createState() => _NsliderNodeBodyState();
}

class _NsliderNodeBodyState extends State<NsliderNodeBody> {
  late final GuiValueLink _gui;
  late StaffNote _note;

  StaffDrag? _drag;
  double _dy = 0;
  int? _sent;

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
  void didUpdateWidget(NsliderNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gui.rebind(widget.node);
  }

  @override
  void dispose() {
    _gui.dispose();
    super.dispose();
  }

  NsliderArgs get _args =>
      NsliderArgs.parse(widget.controller.argsOf(widget.node.id));

  /// The pitch the object holds, from the poll's read.
  int get _pitch => _args.bound(
    int.tryParse(widget.controller.guiValueCellOf(widget.node.id, 0)) ??
        _args.low,
  );

  void _read() {
    final accidental =
        int.tryParse(widget.controller.guiValueCellOf(widget.node.id, 1)) ?? 0;
    _note = StaffNote.of(_pitch, accidental);
  }

  void _follow() {
    if (_drag != null) return;
    setState(_read);
  }

  void _start() {
    _drag = StaffDrag(start: _pitch, args: _args);
    _dy = 0;
    _sent = null;
  }

  void _move(double dy) {
    final drag = _drag;
    if (drag == null) return;
    _dy += dy;
    final pitch = drag.pitchAfter(_dy);
    if (pitch == (_sent ?? drag.start)) return;
    _sent = pitch;
    widget.controller.setControlInt(widget.node.id, inlet: 0, value: pitch);
    // Drawn at once with the spelling the object will give it.
    final spelled = MidiPitch.isBlack(pitch)
        ? (_args.spelling < 0 ? -1 : 1)
        : 0;
    setState(() => _note = StaffNote.of(pitch, spelled));
  }

  void _end() {
    if (_drag == null) return;
    _drag = null;
    setState(_read);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _start(),
      onVerticalDragUpdate: (d) => _move(d.delta.dy),
      onVerticalDragEnd: (_) => _end(),
      onVerticalDragCancel: _end,
      child: PatchStaff(note: _note, voice: widget.node.voice),
    );
  }
}
