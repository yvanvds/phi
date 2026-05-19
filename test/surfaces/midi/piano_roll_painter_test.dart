import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip_seed.dart';
import 'package:phi/surfaces/midi/piano_roll_painter.dart';

void main() {
  group('PianoRollPainter', () {
    test('shouldRepaint compares the version counter', () {
      final a = PianoRollPainter(
        notes: const [],
        bars: 4,
        beatsPerBar: 4,
        version: 1,
      );
      final b = PianoRollPainter(
        notes: const [],
        bars: 4,
        beatsPerBar: 4,
        version: 1,
      );
      final c = PianoRollPainter(
        notes: const [],
        bars: 4,
        beatsPerBar: 4,
        version: 2,
      );

      expect(a.shouldRepaint(b), isFalse);
      expect(a.shouldRepaint(c), isTrue);
    });

    test('paints the seeded phrase without throwing', () {
      final clip = phraseA();
      final painter = PianoRollPainter(
        notes: clip.notes,
        bars: clip.bars,
        beatsPerBar: clip.beatsPerBar,
        version: 0,
      );
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(660, 200));
      recorder.endRecording().dispose();
    });

    test('paints empty input without throwing', () {
      final painter = PianoRollPainter(
        notes: const [],
        bars: 1,
        beatsPerBar: 4,
        version: 0,
      );
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(100, 60));
      recorder.endRecording().dispose();
    });
  });
}
