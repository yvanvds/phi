import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/clip_editor.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/surfaces/midi/piano_roll_editor.dart';
import 'package:phi/surfaces/midi/piano_roll_geometry.dart';
import 'package:phi/surfaces/midi/piano_roll_view.dart';
import 'package:phi/surfaces/midi/snap_grid.dart';

// A wide pitch window so lanes are short — leaving room for vertical zoom-in —
// while beats stay coarse enough to reason about.
const _minPitch = 60;
const _maxPitch = 76;
const _bars = 4;
const _beatsPerBar = 4;

MidiClip _clip(List<MidiNote> notes) => MidiClip(bars: _bars, notes: notes);

void main() {
  late ClipEditor editor;
  PianoRollView? captured;
  PianoRollView? current; // what the parent currently holds

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 240,
              child: StatefulBuilder(
                builder: (context, _) => PianoRollEditor(
                  editor: editor,
                  ghostNotes: const [],
                  showGhost: false,
                  bars: _bars,
                  beatsPerBar: _beatsPerBar,
                  minPitch: _minPitch,
                  maxPitch: _maxPitch,
                  view: current,
                  onViewChanged: (v) => captured = v,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder paintFinder() => find
      .descendant(
        of: find.byType(PianoRollEditor),
        matching: find.byType(CustomPaint),
      )
      .first;

  Rect rollRect(WidgetTester tester) => tester.getRect(paintFinder());

  PianoRollGeometry geoOf(WidgetTester tester, {PianoRollView? view}) =>
      PianoRollGeometry(
        size: rollRect(tester).size,
        bars: _bars,
        beatsPerBar: _beatsPerBar,
        minPitch: _minPitch,
        maxPitch: _maxPitch,
        view: view,
      );

  Offset localToGlobal(WidgetTester tester, Offset local) =>
      rollRect(tester).topLeft + local;

  Future<void> ctrlScrollAt(
    WidgetTester tester,
    Offset localAnchor,
    Offset delta, {
    bool shift = false,
  }) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(localToGlobal(tester, localAnchor));
    await tester.sendEventToBinding(pointer.scroll(delta));
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  setUp(() {
    captured = null;
    current = null;
  });

  group('pointer-anchored zoom (issue #189)', () {
    testWidgets(
      'Ctrl+wheel magnifies horizontally, beat under cursor stays put',
      (tester) async {
        editor = ClipEditor(
          _clip(const []),
          minPitch: _minPitch,
          maxPitch: _maxPitch,
        );
        await pump(tester);

        const anchor = Offset(250, 100);
        final fitBeat = geoOf(tester).beatForX(anchor.dx);

        // Wheel-up (negative dy) = zoom in.
        await ctrlScrollAt(tester, anchor, const Offset(0, -100));

        expect(captured, isNotNull);
        expect(
          captured!.pixelsPerBeat,
          greaterThan(geoOf(tester).pixelsPerBeat),
        );
        // The beat that was under the cursor is still under it after the zoom.
        expect(
          geoOf(tester, view: captured).beatForX(anchor.dx),
          closeTo(fitBeat, 1e-6),
        );
      },
    );

    testWidgets('Ctrl+Shift+wheel magnifies vertically, horizontal untouched', (
      tester,
    ) async {
      editor = ClipEditor(
        _clip(const []),
        minPitch: _minPitch,
        maxPitch: _maxPitch,
      );
      await pump(tester);

      final fitLane = geoOf(tester).laneHeight;
      final fitPixelsPerBeat = geoOf(tester).pixelsPerBeat;

      await ctrlScrollAt(
        tester,
        const Offset(200, 120),
        const Offset(0, -100),
        shift: true,
      );

      expect(captured, isNotNull);
      expect(captured!.laneHeight, greaterThan(fitLane));
      // A vertical gesture leaves the horizontal scale alone.
      expect(captured!.pixelsPerBeat, closeTo(fitPixelsPerBeat, 1e-9));
      expect(captured!.scrollBeats, 0);
    });

    testWidgets('a bare wheel (no Ctrl) does not zoom', (tester) async {
      editor = ClipEditor(
        _clip(const []),
        minPitch: _minPitch,
        maxPitch: _maxPitch,
      );
      await pump(tester);

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(localToGlobal(tester, const Offset(200, 100)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
      await tester.pump();

      expect(captured, isNull);
    });

    testWidgets('Ctrl+= zooms in from the keyboard', (tester) async {
      editor = ClipEditor(
        _clip(const []),
        minPitch: _minPitch,
        maxPitch: _maxPitch,
      );
      await pump(tester);
      final fitPixelsPerBeat = geoOf(tester).pixelsPerBeat;

      // Focus the roll (a tap requests focus; the added note is irrelevant here).
      await tester.tapAt(localToGlobal(tester, const Offset(200, 120)));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(captured, isNotNull);
      expect(captured!.pixelsPerBeat, greaterThan(fitPixelsPerBeat));
    });
  });

  group('snap picker drives gestures (issue #189)', () {
    testWidgets('click-to-add snaps to a triplet grid (1/8T)', (tester) async {
      editor = ClipEditor(
        _clip(const []),
        gridDivision: SnapGrid.eighthTriplet,
        minPitch: _minPitch,
        maxPitch: _maxPitch,
      );
      await pump(tester);

      const local = Offset(213, 100);
      final raw = geoOf(tester).beatForX(local.dx);
      final expected =
          (raw / SnapGrid.eighthTriplet).round() * SnapGrid.eighthTriplet;

      await tester.tapAt(localToGlobal(tester, local));
      await tester.pump();

      expect(editor.clip.notes, hasLength(1));
      expect(editor.clip.notes.single.start, closeTo(expected, 1e-6));
      // The start lands on the triplet grid: a whole number of 1/8T steps.
      final steps = editor.clip.notes.single.start / SnapGrid.eighthTriplet;
      expect(steps, closeTo(steps.roundToDouble(), 1e-6));
    });

    testWidgets('snap off places the note free (no grid rounding)', (
      tester,
    ) async {
      editor = ClipEditor(
        _clip(const []),
        gridDivision: SnapGrid.off,
        minPitch: _minPitch,
        maxPitch: _maxPitch,
      );
      await pump(tester);

      // An x whose beat is deliberately not on any musical grid.
      const local = Offset(197, 100);
      final raw = geoOf(tester).beatForX(local.dx);

      await tester.tapAt(localToGlobal(tester, local));
      await tester.pump();

      expect(editor.clip.notes, hasLength(1));
      // Free placement: the start equals the raw pointer beat, un-rounded.
      expect(editor.clip.notes.single.start, closeTo(raw, 1e-6));
      // With snapping off a fresh note still gets a sensible non-zero length.
      expect(editor.clip.notes.single.duration, 0.25);
    });

    // Grab a wide note a little in from its left edge (so gesture slop keeps the
    // drag on the body, not the right-edge resize zone) and drag it far right.
    // The assertions test the *snapping* the picker drives — grid alignment —
    // not the exact travel, which gesture slop shortens slightly.
    const dragNote = MidiNote(pitch: 66, start: 4, duration: 4, velocity: 0.7);

    Offset grabGlobal(WidgetTester tester) {
      final geo = geoOf(tester);
      return localToGlobal(
        tester,
        Offset(
          geo.xForBeat(dragNote.start) + geo.widthForBeats(0.8),
          geo.yForPitch(dragNote.pitch),
        ),
      );
    }

    testWidgets('drag lands on the grid when a 1/4 snap is picked', (
      tester,
    ) async {
      editor = ClipEditor(
        _clip(const [dragNote]),
        gridDivision: SnapGrid.quarter, // 1 beat
        minPitch: _minPitch,
        maxPitch: _maxPitch,
      );
      await pump(tester);

      await tester.dragFrom(grabGlobal(tester), const Offset(120, 0));
      await tester.pump();

      final moved = editor.clip.notes.single;
      expect(moved.start, greaterThan(4)); // it moved right
      expect(moved.duration, 4); // a move, not a resize
      // Snapped to the 1/4 (whole-beat) grid — an integer number of beats.
      expect(moved.start, closeTo(moved.start.roundToDouble(), 1e-6));
    });

    testWidgets('drag runs free (off the grid) when snapping is off', (
      tester,
    ) async {
      editor = ClipEditor(
        _clip(const [dragNote]),
        gridDivision: SnapGrid.off,
        minPitch: _minPitch,
        maxPitch: _maxPitch,
      );
      await pump(tester);

      await tester.dragFrom(grabGlobal(tester), const Offset(120, 0));
      await tester.pump();

      final moved = editor.clip.notes.single;
      expect(moved.start, greaterThan(4)); // it moved right
      expect(moved.duration, 4); // a move, not a resize
      // Free placement: the landing is not rounded to the quarter grid.
      expect(
        (moved.start - moved.start.roundToDouble()).abs(),
        greaterThan(1e-3),
      );
    });
  });
}
