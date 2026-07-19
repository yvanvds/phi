import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/clip_editor.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/surfaces/midi/piano_roll_editor.dart';

// A narrow 4-semitone window (60–64) makes lanes tall and the caret's "home"
// lane exactly its middle, 62, so a dropped note's pitch is predictable.
const _minPitch = 60;
const _maxPitch = 64;
const _homePitch = 62; // (60 + 64) / 2

MidiClip _clip(List<MidiNote> notes) => MidiClip(bars: 4, notes: notes);

void main() {
  late ClipEditor editor;

  Future<void> pump(WidgetTester tester, {required double grid}) async {
    editor = ClipEditor(
      _clip(const []),
      gridDivision: grid,
      minPitch: _minPitch,
      maxPitch: _maxPitch,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 240,
              child: PianoRollEditor(
                editor: editor,
                ghostNotes: const [],
                showGhost: false,
                bars: 4,
                beatsPerBar: 4,
                minPitch: _minPitch,
                maxPitch: _maxPitch,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // Focus the roll without adding a note (a tap would author one): grab the
  // roll's own Focus node and give it primary focus.
  Future<void> focusRoll(WidgetTester tester) async {
    final focus = tester.widget<Focus>(
      find
          .descendant(
            of: find.byType(PianoRollEditor),
            matching: find.byType(Focus),
          )
          .first,
    );
    focus.focusNode!.requestFocus();
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  bool hasNoteAt(double start, {double? pitch, double? duration}) =>
      editor.clip.notes.any(
        (n) =>
            (n.start - start).abs() < 1e-6 &&
            (pitch == null || (n.pitch - pitch).abs() < 1e-6) &&
            (duration == null || (n.duration - duration).abs() < 1e-6),
      );

  testWidgets('arrows summon the caret; Enter drops a grid-length note there', (
    tester,
  ) async {
    await pump(tester, grid: 0.5); // 1/8 grid
    await focusRoll(tester);

    // From empty the first arrow summons the caret at home (beat 0, lane 62) and
    // moves it: two rights → beat 1.0, one up → lane 63.
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowUp);

    await press(tester, LogicalKeyboardKey.enter);

    expect(editor.clip.notes, hasLength(1));
    expect(hasNoteAt(1.0, pitch: 63, duration: 0.5), isTrue);
  });

  testWidgets('the caret advances by the grid after each entry (1/8)', (
    tester,
  ) async {
    await pump(tester, grid: 0.5);
    await focusRoll(tester);

    // Position at beat 1.0, then drop three notes with Enter alone: the caret
    // advances a grid step (0.5) after each, laying them end to end.
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.enter); // 1.0
    await press(tester, LogicalKeyboardKey.enter); // 1.5
    await press(tester, LogicalKeyboardKey.enter); // 2.0

    expect(editor.clip.notes, hasLength(3));
    expect(hasNoteAt(1.0, pitch: _homePitch.toDouble()), isTrue);
    expect(hasNoteAt(1.5, pitch: _homePitch.toDouble()), isTrue);
    expect(hasNoteAt(2.0, pitch: _homePitch.toDouble()), isTrue);
  });

  testWidgets('the caret steps by a sixteenth on a 1/16 grid', (tester) async {
    await pump(tester, grid: 0.25); // 1/16 grid
    await focusRoll(tester);

    await press(tester, LogicalKeyboardKey.arrowRight); // 0 → 0.25
    await press(tester, LogicalKeyboardKey.enter); // drop 0.25, advance 0.5
    await press(tester, LogicalKeyboardKey.enter); // drop 0.5

    expect(editor.clip.notes, hasLength(2));
    expect(hasNoteAt(0.25, duration: 0.25), isTrue);
    expect(hasNoteAt(0.5, duration: 0.25), isTrue);
  });

  testWidgets('Escape dismisses the caret (Enter then summons a fresh one)', (
    tester,
  ) async {
    await pump(tester, grid: 1.0); // 1/4 grid
    await focusRoll(tester);

    // Move the caret out to beat 2.0, then dismiss it.
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.escape);

    // With the caret dismissed, Enter summons a fresh one at the origin and
    // drops there — proving the moved-out caret was gone, not at beat 2.0.
    await press(tester, LogicalKeyboardKey.enter);

    expect(editor.clip.notes, hasLength(1));
    expect(hasNoteAt(0.0, pitch: _homePitch.toDouble()), isTrue);
  });

  testWidgets('arrows still nudge a selection when no caret is up', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox()); // reset before custom clip
    editor = ClipEditor(
      _clip(const [MidiNote(pitch: 62, start: 4, duration: 1, velocity: 0.7)]),
      gridDivision: 1.0,
      minPitch: _minPitch,
      maxPitch: _maxPitch,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 240,
              child: PianoRollEditor(
                editor: editor,
                ghostNotes: const [],
                showGhost: false,
                bars: 4,
                beatsPerBar: 4,
                minPitch: _minPitch,
                maxPitch: _maxPitch,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    editor.selectOnly(0);
    await focusRoll(tester);

    // No caret is up and a note is selected, so the arrow nudges it (the legacy
    // #189/#190 behaviour) rather than summoning a caret.
    await press(tester, LogicalKeyboardKey.arrowRight);

    expect(editor.clip.notes, hasLength(1));
    expect(editor.clip.notes.single.start, 5.0);
  });
}
