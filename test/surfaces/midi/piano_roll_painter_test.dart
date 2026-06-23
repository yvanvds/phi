import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip_seed.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/surfaces/midi/piano_roll_painter.dart';

PianoRollPainter _painter({
  List<MidiNote> source = const [],
  List<MidiNote> ghost = const [],
  Set<int> selection = const {},
  int revision = 0,
  Rect? marquee,
  bool showGhost = true,
}) => PianoRollPainter(
  sourceNotes: source,
  ghostNotes: ghost,
  selection: selection,
  bars: 4,
  beatsPerBar: 4,
  revision: revision,
  marquee: marquee,
  showGhost: showGhost,
);

void main() {
  group('PianoRollPainter', () {
    test('shouldRepaint tracks the revision counter', () {
      expect(
        _painter(revision: 1).shouldRepaint(_painter(revision: 1)),
        isFalse,
      );
      expect(
        _painter(revision: 2).shouldRepaint(_painter(revision: 1)),
        isTrue,
      );
    });

    test('shouldRepaint reacts to selection and source changes', () {
      const note = MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1);
      final base = _painter(source: const [note]);
      expect(base.shouldRepaint(_painter(source: const [note])), isFalse);
      expect(
        base.shouldRepaint(_painter(source: const [note], selection: {0})),
        isTrue,
      );
      expect(base.shouldRepaint(_painter(source: const [])), isTrue);
    });

    test('shouldRepaint reacts to the marquee rectangle', () {
      final base = _painter();
      expect(
        base.shouldRepaint(
          _painter(marquee: const Rect.fromLTWH(0, 0, 10, 10)),
        ),
        isTrue,
      );
    });

    test('paints the seeded phrase with a ghost layer without throwing', () {
      final clip = phraseA();
      final painter = _painter(
        source: clip.notes,
        ghost: clip.notes,
        selection: {0, 2},
        marquee: const Rect.fromLTWH(10, 10, 40, 40),
      );
      final recorder = PictureRecorder();
      painter.paint(Canvas(recorder), const Size(660, 200));
      recorder.endRecording().dispose();
    });

    test('paints empty input without throwing', () {
      final recorder = PictureRecorder();
      _painter().paint(Canvas(recorder), const Size(100, 60));
      recorder.endRecording().dispose();
    });
  });
}
