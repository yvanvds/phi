import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/clip_editor.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/surfaces/midi/piano_roll_editor.dart';
import 'package:phi/surfaces/midi/piano_roll_geometry.dart';

const _minPitch = 60;
const _maxPitch = 64;

MidiClip _clip(List<MidiNote> notes) => MidiClip(bars: 4, notes: notes);

/// Roll audition (design §7, issue #211): clicking a note or stepping one in
/// previews it through its routed voice via [PianoRollEditor.onAuditionNote].
void main() {
  late ClipEditor editor;
  late List<MidiNote> audited;

  Future<void> pump(WidgetTester tester) async {
    audited = [];
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
                onAuditionNote: audited.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

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

  testWidgets('clicking a note previews it through its routed voice', (
    tester,
  ) async {
    const note = MidiNote(
      pitch: 62,
      start: 4,
      duration: 4,
      velocity: 0.7,
      voice: 'voice.bass',
    );
    editor = ClipEditor(
      _clip(const [note]),
      minPitch: _minPitch,
      maxPitch: _maxPitch,
    );
    await pump(tester);

    await tester.tapAt(noteCenter(tester, note));
    await tester.pump();

    expect(editor.selection, {0});
    expect(audited, hasLength(1));
    expect(audited.single.pitch, 62);
    expect(audited.single.voice, 'voice.bass');
  });

  testWidgets('clicking an empty cell previews the note it adds', (
    tester,
  ) async {
    editor = ClipEditor(
      _clip(const []),
      minPitch: _minPitch,
      maxPitch: _maxPitch,
    );
    await pump(tester);

    await tester.tapAt(origin(tester) + const Offset(150, 120));
    await tester.pump();

    expect(editor.clip.notes, hasLength(1));
    expect(audited, hasLength(1));
    expect(audited.single.pitch, editor.clip.notes.single.pitch);
  });

  testWidgets('caret step-entry previews the stepped note', (tester) async {
    editor = ClipEditor(
      _clip(const []),
      minPitch: _minPitch,
      maxPitch: _maxPitch,
    );
    await pump(tester);

    // Focus the roll, then summon the caret with an arrow and drop with Enter.
    await tester.tapAt(origin(tester) + const Offset(150, 120));
    await tester.pump();
    audited.clear();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(audited, isNotEmpty);
  });
}
