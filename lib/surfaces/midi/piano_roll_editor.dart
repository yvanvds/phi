import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/midi/clip_editor.dart';
import '../../domain/midi/midi_note.dart';
import 'piano_roll_caret.dart';
import 'piano_roll_geometry.dart';
import 'piano_roll_painter.dart';
import 'piano_roll_scrollbar.dart';
import 'piano_roll_view.dart';

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
    this.playhead,
    this.view,
    this.onViewChanged,
    super.key,
  });

  final ClipEditor editor;
  final List<MidiNote> ghostNotes;
  final bool showGhost;
  final int bars;
  final int beatsPerBar;
  final int minPitch;
  final int maxPitch;

  /// The engine player's beat position (issue #29). When `null` the roll
  /// paints no playhead; otherwise it animates as the player advances.
  final ValueListenable<double>? playhead;

  /// Session-local pan/zoom (issue #189). `null` fits the whole clip to the
  /// paint area (the un-zoomed default). Zoom gestures — Ctrl+wheel horizontal
  /// (pointer-anchored), Ctrl+Shift+wheel vertical, `Ctrl+=` / `Ctrl+-` — emit a
  /// new view through [onViewChanged]; the parent owns it so the velocity lane
  /// shares the same horizontal scale.
  final PianoRollView? view;

  /// Called with a fresh [PianoRollView] on every zoom gesture. `null` makes the
  /// roll un-zoomable (the wheel/keys are ignored) — used by tests and previews
  /// that want the plain fitted roll.
  final ValueChanged<PianoRollView>? onViewChanged;

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

  /// The step-entry caret (issue #191), or `null` when none is summoned. The
  /// arrow keys move it by one grid step; `Enter` drops a grid-length note at its
  /// lane/beat and advances it; `Escape` dismisses it. Pure view state — a note is
  /// authored through [ClipEditor] like any other edit, so it undoes normally.
  PianoRollCaret? _caret;

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
    view: widget.view,
  );

  double get _grid => _editor.gridDivision;

  /// Snap [beats] to the grid, or pass it through untouched when snapping is
  /// off (`gridDivision <= 0`, the picker's "off").
  double _snap(double beats) =>
      _grid > 0 ? (beats / _grid).round() * _grid : beats;

  /// Step for a fresh note's duration and an arrow-key nudge — the grid, or a
  /// sensible default when snapping is off so both still do something useful.
  double get _step => _grid > 0 ? _grid : _defaultStep;
  static const double _defaultStep = 0.25;

  bool get _shift => HardwareKeyboard.instance.isShiftPressed;
  bool get _ctrl => HardwareKeyboard.instance.isControlPressed;

  // ── Zoom (issue #189) ─────────────────────────────────────────────────────

  static const double _wheelZoomIn = 1.15;
  static const double _wheelZoomOut = 1 / 1.15;
  static const double _keyZoomIn = 1.2;
  static const double _keyZoomOut = 1 / 1.2;

  int get _beatSpan {
    final span = widget.bars * widget.beatsPerBar;
    return span <= 0 ? 1 : span;
  }

  int get _pitchSpan => (widget.maxPitch - widget.minPitch).clamp(1, 127);

  double get _fitPixelsPerBeat =>
      _size.width <= 0 ? 1 : _size.width / _beatSpan;
  double get _fitLaneHeight =>
      _size.height <= 0 ? 1 : _size.height / _pitchSpan;

  /// The current view, or a fit-to-size one synthesised from the paint area when
  /// the roll has not been zoomed yet — so the first zoom anchors off the
  /// fitted scale.
  PianoRollView get _effectiveView =>
      widget.view ??
      PianoRollView(
        pixelsPerBeat: _fitPixelsPerBeat,
        laneHeight: _fitLaneHeight,
      );

  void _zoomHorizontal(double factor, double anchorX) {
    final onChanged = widget.onViewChanged;
    if (onChanged == null || _size.width <= 0) return;
    onChanged(
      _effectiveView.zoomedHorizontally(
        factor: factor,
        anchorX: anchorX,
        viewportWidth: _size.width,
        beatSpan: _beatSpan,
        minPixelsPerBeat: _fitPixelsPerBeat,
      ),
    );
  }

  void _zoomVertical(double factor, double anchorY) {
    final onChanged = widget.onViewChanged;
    if (onChanged == null || _size.height <= 0) return;
    onChanged(
      _effectiveView.zoomedVertically(
        factor: factor,
        anchorY: anchorY,
        viewportHeight: _size.height,
        laneSpan: _pitchSpan,
        minLaneHeight: _fitLaneHeight,
      ),
    );
  }

  // ── Pan (issue #198) ──────────────────────────────────────────────────────

  /// Pan the zoomed view by a pointer delta (middle-drag). Only acts once the
  /// roll has been zoomed (a non-null [PianoRollEditor.view]) — the fitted roll
  /// has nothing to pan, and emitting a view there would freeze the auto-fit
  /// scale against later resizes. Both axes clamp through the same bounds zoom
  /// uses, so a drag can never run the clip off an edge.
  void _panBy(Offset delta) {
    final view = widget.view;
    final onChanged = widget.onViewChanged;
    if (view == null || onChanged == null || _size.isEmpty) return;
    onChanged(
      view.pannedBy(
        dxPixels: delta.dx,
        dyPixels: delta.dy,
        viewportWidth: _size.width,
        viewportHeight: _size.height,
        beatSpan: _beatSpan,
        laneSpan: _pitchSpan,
      ),
    );
  }

  /// Middle-mouse drag pans the roll (issue #198) — a conflict-free companion to
  /// the scrollbars that leaves the left button free for editing. Tracked on the
  /// enclosing [Listener] so it works anywhere over the roll, not just the thin
  /// scrollbar strips.
  bool _middlePanning = false;

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons == kMiddleMouseButton) _middlePanning = true;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_middlePanning && event.buttons == kMiddleMouseButton) {
      _panBy(event.delta);
    }
  }

  void _onPointerUp(PointerUpEvent event) => _middlePanning = false;

  /// Ctrl+wheel zooms: horizontal by default (anchored on the pointer's beat),
  /// vertical with Shift held. A bare wheel scroll is left alone.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_ctrl) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;
    final zoomIn = dy < 0; // wheel-up (negative delta) magnifies
    if (_shift) {
      _zoomVertical(
        zoomIn ? _wheelZoomIn : _wheelZoomOut,
        event.localPosition.dy,
      );
    } else {
      _zoomHorizontal(
        zoomIn ? _wheelZoomIn : _wheelZoomOut,
        event.localPosition.dx,
      );
    }
  }

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
        pitch: _geo.pitchForY(d.localPosition.dy).toDouble(),
        start: _snap(
          _geo.beatForX(d.localPosition.dx),
        ).clamp(0.0, double.infinity),
        duration: _step,
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
      // Ctrl+= / Ctrl+- zoom horizontally around the roll's centre (issue #189).
      // Everything else (Ctrl+Z/Y) bubbles: the shell routes undo/redo to the
      // focused surface's stack (undo follows focus, #119).
      switch (key) {
        case LogicalKeyboardKey.equal:
        case LogicalKeyboardKey.add:
        case LogicalKeyboardKey.numpadAdd:
          _zoomHorizontal(_keyZoomIn, _size.width / 2);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.minus:
        case LogicalKeyboardKey.numpadSubtract:
          _zoomHorizontal(_keyZoomOut, _size.width / 2);
          return KeyEventResult.handled;
        default:
          return KeyEventResult.ignored;
      }
    }
    switch (key) {
      case LogicalKeyboardKey.arrowUp:
        _arrow(dPitch: 1);
      case LogicalKeyboardKey.arrowDown:
        _arrow(dPitch: -1);
      case LogicalKeyboardKey.arrowLeft:
        _arrow(dBeats: -_step);
      case LogicalKeyboardKey.arrowRight:
        _arrow(dBeats: _step);
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _dropAtCaret();
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        _editor.deleteSelection();
      case LogicalKeyboardKey.escape:
        if (_caret != null) {
          setState(() => _caret = null);
        } else {
          _editor.clearSelection();
        }
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ── Step entry: the caret (issue #191) ────────────────────────────────────

  /// The lane a freshly-summoned caret sits on — the middle of the visible pitch
  /// window, so the first step-entry note lands somewhere on-screen.
  int get _homePitch => ((widget.minPitch + widget.maxPitch) / 2).round();

  /// A caret at the resting origin — beat 0, middle lane.
  PianoRollCaret get _home => PianoRollCaret(beat: 0, pitch: _homePitch);

  /// An arrow key. The caret wins when it is up (step entry); otherwise a
  /// selection is nudged as before (#189/#190); with neither, the arrow summons
  /// the caret and moves it, so an empty roll enters step mode on the first press.
  void _arrow({int dPitch = 0, double dBeats = 0}) {
    if (_caret != null) {
      _moveCaret(dPitch: dPitch, dBeats: dBeats);
    } else if (_editor.selection.isNotEmpty) {
      _editor.moveSelection(dPitch: dPitch, dBeats: dBeats);
    } else {
      setState(() => _caret = _home);
      _moveCaret(dPitch: dPitch, dBeats: dBeats);
    }
  }

  /// Move the caret by one grid step, clamped to the clip origin and the visible
  /// pitch window.
  void _moveCaret({int dPitch = 0, double dBeats = 0}) {
    final c = _caret;
    if (c == null) return;
    setState(() {
      _caret = c.copyWith(
        beat: (c.beat + dBeats).clamp(0.0, double.infinity),
        pitch: (c.pitch + dPitch).clamp(widget.minPitch, widget.maxPitch),
      );
    });
  }

  /// Drop a grid-length note at the caret (summoning one at the origin first when
  /// none is up), then advance the caret by the grid so a run of `Enter`s lays
  /// notes end to end. The add goes through [ClipEditor], so it undoes normally.
  void _dropAtCaret() {
    final c = _caret ?? _home;
    _editor.addNote(
      MidiNote(
        pitch: c.pitch.toDouble(),
        start: c.beat,
        duration: _step,
        velocity: 0.7,
      ),
    );
    setState(() => _caret = c.copyWith(beat: c.beat + _step));
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
          pitch: (n.pitch + _dPitch).clamp(
            widget.minPitch.toDouble(),
            widget.maxPitch.toDouble(),
          ),
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

  /// The painted roll. When a [PianoRollEditor.playhead] is supplied, the
  /// `CustomPaint` is wrapped in a [ValueListenableBuilder] so the player's
  /// per-tick beat updates repaint only the painter (not the gesture layer or
  /// the surrounding chrome). `_displayNotes()` is read inside the builder so
  /// an in-flight drag still tracks the pointer while the playhead animates.
  Widget _buildRoll() {
    final playhead = widget.playhead;
    if (playhead == null) return _painter(0);
    return ValueListenableBuilder<double>(
      valueListenable: playhead,
      builder: (context, beat, _) => _painter(beat),
    );
  }

  /// Overlay scrollbars for the zoomed roll (issue #198). They float over the
  /// content edges (rather than reserving space) so the painter keeps the full
  /// paint area and every existing fit/zoom arithmetic is untouched; each bar
  /// hides itself when its axis already fits. Dragging a thumb reports a fresh
  /// clamped scroll through the same view the middle-drag and zoom use, so the
  /// velocity lane — which shares the view — tracks the horizontal one for free.
  List<Widget> _scrollbars() {
    final view = widget.view;
    final onChanged = widget.onViewChanged;
    if (view == null || onChanged == null || _size.isEmpty) return const [];
    const t = PianoRollScrollbar.defaultThickness;
    return [
      Positioned(
        left: 0,
        right: t,
        bottom: 0,
        height: t,
        child: PianoRollScrollbar(
          axis: Axis.horizontal,
          contentExtent: _beatSpan.toDouble(),
          viewportExtent: _size.width / view.pixelsPerBeat,
          offset: view.scrollBeats,
          onScrollTo: (beats) => onChanged(
            view.withScrollBeats(
              beats,
              viewportWidth: _size.width,
              beatSpan: _beatSpan,
            ),
          ),
        ),
      ),
      Positioned(
        top: 0,
        right: 0,
        bottom: t,
        width: t,
        child: PianoRollScrollbar(
          axis: Axis.vertical,
          contentExtent: _pitchSpan.toDouble(),
          viewportExtent: _size.height / view.laneHeight,
          offset: view.scrollLanes,
          onScrollTo: (lanes) => onChanged(
            view.withScrollLanes(
              lanes,
              viewportHeight: _size.height,
              laneSpan: _pitchSpan,
            ),
          ),
        ),
      ),
    ];
  }

  Widget _painter(double playhead) => CustomPaint(
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
      playhead: playhead,
      view: widget.view,
      caret: _caret,
      caretLength: _step,
    ),
  );

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
                  child: Listener(
                    onPointerSignal: _onPointerSignal,
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerUp: _onPointerUp,
                    onPointerCancel: (_) => _middlePanning = false,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: _onTapUp,
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: _onPanEnd,
                      child: _buildRoll(),
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
                ..._scrollbars(),
              ],
            );
          },
        ),
      ),
    );
  }
}
