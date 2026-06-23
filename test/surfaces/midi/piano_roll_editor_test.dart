import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/clip_editor.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/surfaces/midi/piano_roll_editor.dart';
import 'package:phi/surfaces/midi/piano_roll_geometry.dart';

// A narrow 4-semitone window makes lanes ~tall, so taps land squarely on a
// note regardless of the 1px container border inset.
const _minPitch = 60;
const _maxPitch = 64;

MidiClip _clip(List<MidiNote> notes) =>
    MidiClip(name: 't', bars: 4, notes: notes);

void main() {
  late ClipEditor editor;

  Future<void> pump(WidgetTester tester) async {
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

  // Geometry over the actual painted area, so global coordinates are exact.
  PianoRollGeometry geoOf(WidgetTester tester) {
    final size = tester
        .getRect(
          find.descendant(
            of: find.byType(PianoRollEditor),
            matching: find.byType(CustomPaint),
          ),
        )
        .size;
    return PianoRollGeometry(
      size: size,
      bars: 4,
      beatsPerBar: 4,
      minPitch: _minPitch,
      maxPitch: _maxPitch,
    );
  }

  Offset origin(WidgetTester tester) => tester.getTopLeft(
    find.descendant(
      of: find.byType(PianoRollEditor),
      matching: find.byType(CustomPaint),
    ),
  );

  Offset noteCenter(WidgetTester tester, MidiNote n) {
    final geo = geoOf(tester);
    return origin(tester) +
        Offset(
          geo.xForBeat(n.start) + geo.widthForBeats(n.duration) / 2,
          geo.yForPitch(n.pitch),
        );
  }

  testWidgets('tap on an empty cell adds a note', (tester) async {
    editor = ClipEditor(
      _clip(const []),
      minPitch: _minPitch,
      maxPitch: _maxPitch,
    );
    await pump(tester);

    await tester.tapAt(origin(tester) + const Offset(150, 120));
    await tester.pump();

    expect(editor.clip.notes, hasLength(1));
    expect(editor.selection, {0});
  });

  testWidgets('tap selects a note, Delete removes it', (tester) async {
    const note = MidiNote(pitch: 62, start: 4, duration: 4, velocity: 0.7);
    editor = ClipEditor(
      _clip(const [note]),
      minPitch: _minPitch,
      maxPitch: _maxPitch,
    );
    await pump(tester);

    await tester.tapAt(noteCenter(tester, note));
    await tester.pump();
    expect(editor.selection, {0});

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(editor.clip.notes, isEmpty);
  });

  testWidgets('dragging a note body moves it up in pitch', (tester) async {
    const note = MidiNote(pitch: 61, start: 4, duration: 4, velocity: 0.7);
    editor = ClipEditor(
      _clip(const [note]),
      minPitch: _minPitch,
      maxPitch: _maxPitch,
    );
    await pump(tester);

    final geo = geoOf(tester);
    // Drag straight up by one full lane → +1 semitone, no time change.
    await tester.dragFrom(noteCenter(tester, note), Offset(0, -geo.laneHeight));
    await tester.pump();

    expect(editor.clip.notes[0].pitch, greaterThan(61));
    expect(editor.clip.notes[0].start, 4);
  });

  testWidgets('Ctrl+Z undoes the last edit', (tester) async {
    const note = MidiNote(pitch: 61, start: 4, duration: 4, velocity: 0.7);
    editor = ClipEditor(
      _clip(const [note]),
      minPitch: _minPitch,
      maxPitch: _maxPitch,
    );
    await pump(tester);

    final geo = geoOf(tester);
    await tester.dragFrom(noteCenter(tester, note), Offset(0, -geo.laneHeight));
    await tester.pump();
    expect(editor.clip.notes[0].pitch, isNot(61));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(editor.clip.notes[0].pitch, 61);
  });

  testWidgets('marquee drag selects the enclosed notes', (tester) async {
    editor = ClipEditor(
      _clip(const [
        MidiNote(pitch: 61, start: 4, duration: 0.5, velocity: 0.7),
        MidiNote(pitch: 62, start: 8, duration: 0.5, velocity: 0.7),
      ]),
      minPitch: _minPitch,
      maxPitch: _maxPitch,
    );
    await pump(tester);

    final o = origin(tester);
    // Start in an empty top-left corner, sweep a box that encloses both notes.
    await tester.dragFrom(o + const Offset(2, 2), const Offset(320, 230));
    await tester.pump();

    expect(editor.selection, {0, 1});
  });
}
