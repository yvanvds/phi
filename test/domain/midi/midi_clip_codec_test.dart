import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_clip_codec.dart';
import 'package:phi/domain/midi/midi_note.dart';

void main() {
  group('MidiClipCodec', () {
    const codec = MidiClipCodec();

    MidiClip clip() => MidiClip(
      name: 'phrase A',
      bars: 4,
      beatsPerBar: 4,
      notes: const [
        MidiNote(pitch: 60.5, start: 0, duration: 0.25, velocity: 0.7),
        MidiNote(pitch: 67, start: 1, duration: 0.5, velocity: 0.6, channel: 2),
      ],
    );

    test('declares schema version 1', () {
      expect(codec.version, 1);
    });

    test('round-trips a clip source (meter + fractional pitch + channel)', () {
      final encoded = codec.encode(clip());
      final decoded = codec.decode(encoded, 1)! as MidiClip;

      expect(decoded.name, 'phrase A');
      expect(decoded.bars, 4);
      expect(decoded.beatsPerBar, 4);
      expect(decoded.notes, hasLength(2));
      expect(decoded.notes[0].pitch, 60.5);
      expect(decoded.notes[0].velocity, closeTo(0.7, 1e-9));
      expect(decoded.notes[1].pitch, 67);
      expect(decoded.notes[1].channel, 2);
    });

    test('encoded form is a JSON-compatible map', () {
      final encoded = codec.encode(clip())! as Map<String, Object?>;
      expect(encoded['name'], 'phrase A');
      expect(encoded['notes'], isA<List<Object?>>());
    });

    test('null round-trips as null', () {
      expect(codec.encode(null), isNull);
      expect(codec.decode(null, 1), isNull);
    });

    test('decode tolerates a clip with no notes', () {
      final decoded =
          codec.decode(const {'name': 'empty', 'bars': 2}, 1)! as MidiClip;
      expect(decoded.notes, isEmpty);
      expect(decoded.bars, 2);
    });
  });
}
