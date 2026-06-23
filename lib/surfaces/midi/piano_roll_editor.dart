import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/midi/clip_editor.dart';
import '../../domain/midi/midi_note.dart';
import 'piano_roll_geometry.dart';
import 'piano_roll_painter.dart';

/// The interactive piano roll: hit-tests, drags and keyboard edits on top of
/// [PianoRollPainter]. Gestures author the **source** clip through [editor];
/// the transformed [ghostNotes] paint dim behind so the chain's result stays
/// visible while you edit (issue #28).
///
/// A drag previews locally (the painter follows the pointer) and commits a
/// single [ClipEditor] command on release, so each gesture is one undo step.
class PianoRollEditor extends StatefulWidget {
  const PianoRollEditor({
    required this.editor,
    required this.ghostNotes,
    required this.showGhost,
    required this.bars,
    required this.beatsPerBar,
    this.minPitch = 55,
    this.maxPitch = 76,
    super.key,
  });

  final ClipEditor editor;
  final List<MidiNote> ghostNotes;
  final bool showGhost;
  final int bars;
  final int beatsPerBar;
  final int minPitch;
  final int maxPitch;

  @override
  State<PianoRollEditor> createState() => _PianoRollEditorState();
}

enum _DragMode { none, move, resizeRight, moveStart, marquee }

class _PianoRollEditorState extends State<PianoRollEditor> {
  final FocusNode _focus = FocusNode(debugLabel: 'piano-roll');
  Size _size = Size.zero;

  _DragMode _mode = _DragMode.none;
  Offset _dragStart = Offset.zero;
  bool _marqueeAdditive = false;
  Rect? _marquee;

  // Live deltas for a move/resize drag (in semitones / beats).
  int _dPitch = 0;
  double _dBeats = 0;

  ClipEditor get _editor => widget.editor;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  PianoRollGeometry get _geo => PianoRollGeometry(
    size: _size,
    bars: widget.bars,
    beatsPerBar: widget.beatsPerBar,
    minPitch: widget.minPitch,
    maxPitch: widget.maxPitch,
  );

  double get _grid => _editor.gridDivision;
  double _snap(double beats) => (beats / _grid).round() * _grid;

  bool get _shift => HardwareKeyboard.instance.isShiftPressed;
  bool get _ctrl => HardwareKeyboard.instance.isControlPressed;

  // ── Tap: select or add ────────────────────────────────────────────────────

  void _onTapUp(TapUpDetails d) {
    _focus.requestFocus();
    final hit = _geo.hitTest(_editor.clip.notes, d.localPosition);
    if (hit != null) {
      _shift ? _editor.toggle(hit.index) : _editor.selectOnly(hit.index);
      return;
    }
    // Empty cell → add a note snapped to the grid at the clicked lane.
    _editor.addNote(
      MidiNote(
        pitch: _geo.pitchForY(d.localPosition.dy),
        start: _snap(
          _geo.beatForX(d.localPosition.dx),
        ).clamp(0.0, double.infinity),
        duration: _grid,
        velocity: 0.7,
      ),
    );
  }

  // ── Drag: move / resize / marquee ─────────────────────────────────────────

  void _onPanStart(DragStartDetails d) {
    _focus.requestFocus();
    _dragStart = d.localPosition;
    _dPitch = 0;
    _dBeats = 0;
    final hit = _geo.hitTest(_editor.clip.notes, d.localPosition);
    if (hit == null) {
      _mode = _DragMode.marquee;
      _marqueeAdditive = _shift;
      setState(
        () => _marquee = Rect.fromPoints(d.localPosition, d.localPosition),
      );
      return;
    }
    if (!_editor.isSelected(hit.index)) {
      _shift
          ? _editor.setSelection({..._editor.selection, hit.index})
          : _editor.selectOnly(hit.index);
    }
    _mode = switch (hit.edge) {
      NoteEdge.body => _DragMode.move,
      NoteEdge.left => _DragMode.moveStart,
      NoteEdge.right => _DragMode.resizeRight,
    };
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_mode == _DragMode.marquee) {
      setState(() => _marquee = Rect.fromPoints(_dragStart, d.localPosition));
      return;
    }
    final dxBeats = _snap(
      _geo.beatForX(d.localPosition.dx) - _geo.beatForX(_dragStart.dx),
    );
    final dPitch =
        _geo.pitchForY(d.localPosition.dy) - _geo.pitchForY(_dragStart.dy);
    setState(() {
      _dBeats = dxBeats;
      _dPitch = _mode == _DragMode.move ? dPitch : 0;
    });
  }

  void _onPanEnd(DragEndDetails d) {
    if (_mode == _DragMode.marquee) {
      _applyMarquee();
    } else {
      switch (_mode) {
        case _DragMode.move:
          _editor.moveSelection(dPitch: _dPitch, dBeats: _dBeats);
        case _DragMode.moveStart:
          _editor.moveSelection(dBeats: _dBeats);
        case _DragMode.resizeRight:
          _editor.resizeSelection(_dBeats);
        case _DragMode.none:
        case _DragMode.marquee:
          break;
      }
    }
    setState(() {
      _mode = _DragMode.none;
      _marquee = null;
      _dPitch = 0;
      _dBeats = 0;
    });
  }

  void _applyMarquee() {
    final rect = _marquee;
    if (rect == null) return;
    final hits = <int>{};
    final notes = _editor.clip.notes;
    for (var i = 0; i < notes.length; i++) {
      if (_geo.hitRect(notes[i]).overlaps(rect)) hits.add(i);
    }
    _editor.setSelection(
      _marqueeAdditive ? {..._editor.selection, ...hits} : hits,
    );
  }

  // ── Keyboard ──────────────────────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (_ctrl) {
      if (key == LogicalKeyboardKey.keyZ) {
        _shift ? _editor.redo() : _editor.undo();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY) {
        _editor.redo();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    switch (key) {
      case LogicalKeyboardKey.arrowUp:
        _editor.moveSelection(dPitch: 1);
      case LogicalKeyboardKey.arrowDown:
        _editor.moveSelection(dPitch: -1);
      case LogicalKeyboardKey.arrowLeft:
        _editor.moveSelection(dBeats: -_grid);
      case LogicalKeyboardKey.arrowRight:
        _editor.moveSelection(dBeats: _grid);
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        _editor.deleteSelection();
      case LogicalKeyboardKey.escape:
        _editor.clearSelection();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Source notes with the in-flight drag delta applied to the selection, so
  /// the roll tracks the pointer before the edit is committed.
  List<MidiNote> _displayNotes() {
    final notes = _editor.clip.notes;
    if (_mode == _DragMode.none || (_dPitch == 0 && _dBeats == 0)) {
      return notes;
    }
    final sel = _editor.selection;
    return [
      for (var i = 0; i < notes.length; i++)
        if (sel.contains(i)) _previewNote(notes[i]) else notes[i],
    ];
  }

  MidiNote _previewNote(MidiNote n) {
    switch (_mode) {
      case _DragMode.move:
        return n.copyWith(
          pitch: (n.pitch + _dPitch).clamp(widget.minPitch, widget.maxPitch),
          start: (n.start + _dBeats).clamp(0.0, double.infinity),
        );
      case _DragMode.moveStart:
        return n.copyWith(
          start: (n.start + _dBeats).clamp(0.0, double.infinity),
        );
      case _DragMode.resizeRight:
        final dur = n.duration + _dBeats;
        return n.copyWith(duration: dur < _grid ? _grid : dur);
      case _DragMode.none:
      case _DragMode.marquee:
        return n;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Container(
        decoration: BoxDecoration(
          color: PhiColors.bg0,
          border: Border.all(color: PhiColors.line1),
          borderRadius: PhiRadii.all2,
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _size = Size(constraints.maxWidth, constraints.maxHeight);
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: _onTapUp,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: PianoRollPainter(
                        sourceNotes: _displayNotes(),
                        ghostNotes: widget.ghostNotes,
                        selection: _editor.selection,
                        bars: widget.bars,
                        beatsPerBar: widget.beatsPerBar,
                        revision: _editor.revision,
                        marquee: _marquee,
                        showGhost: widget.showGhost,
                        minPitch: widget.minPitch,
                        maxPitch: widget.maxPitch,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 8,
                  child: IgnorePointer(
                    child: Text(
                      'p${widget.minPitch}–${widget.maxPitch} · ${widget.bars} bars'
                          .toUpperCase(),
                      style: PhiType.caption().copyWith(color: PhiColors.fg3),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
