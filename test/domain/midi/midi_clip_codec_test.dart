import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_clip_codec.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';

void main() {
  group('MidiClipCodec', () {
    const codec = MidiClipCodec();

    MidiClip clip() => MidiClip(
      bars: 4,
      beatsPerBar: 4,
      notes: const [
        MidiNote(pitch: 60.5, start: 0, duration: 0.25, velocity: 0.7),
        MidiNote(pitch: 67, start: 1, duration: 0.5, velocity: 0.6, channel: 2),
      ],
    );

    ClipDocument document() => ClipDocument(
      source: clip(),
      chain: const [TransposeTransform(semitones: 12, label: 'up')],
    );

    test('declares schema version 2 (source + interpretation)', () {
      expect(codec.version, 2);
    });

    test('encodes a ClipDocument to a v2 map (source + chain)', () {
      final encoded = codec.encode(document())! as Map<String, Object?>;
      expect(encoded['source'], isA<Map<String, Object?>>());
      expect(encoded['mode'], 'chain');
      expect(encoded['chain'], hasLength(1));
      // Loop defaults on and travels in the document payload (issue #184).
      expect(encoded['loop'], isTrue);
      final source = (encoded['source']! as Map).cast<String, Object?>();
      // The source carries no display name — one-name re-alignment (issue #184).
      expect(source.containsKey('name'), isFalse);
      expect(source['notes'], hasLength(2));
    });

    test('round-trips a full document through decode', () {
      final encoded = codec.encode(document())! as Map<String, Object?>;
      final decoded = codec.decode(encoded, 2)! as Map<String, Object?>;
      // Rebuild the domain document from the normalised map.
      final doc = ClipDocument.fromJson(decoded);
      expect(doc.source.notes, hasLength(2));
      expect(doc.source.notes[0].pitch, 60.5);
      expect(doc.chain, hasLength(1));
      final t = doc.chain.single as TransposeTransform;
      expect(t.semitones, 12);
      expect(t.label, 'up');
    });

    test('migrates a v1 payload (bare clip) forward to a document', () {
      // A v1 file carried the bare source clip, no `source` sub-map or chain.
      // Its `name` is legacy cruft the codec now simply ignores (issue #184).
      final v1 = <String, Object?>{
        'name': 'legacy',
        'bars': 2,
        'beatsPerBar': 4,
        'notes': [
          {
            'pitch': 60,
            'start': 0,
            'duration': 1,
            'velocity': 0.5,
            'channel': 0,
          },
        ],
      };
      final decoded = codec.decode(v1, 1)! as Map<String, Object?>;
      expect(decoded['source'], isA<Map<String, Object?>>());
      expect(decoded['chain'], isEmpty);
      final doc = ClipDocument.fromJson(decoded);
      expect(doc.source.notes, hasLength(1));
      expect(doc.chain, isEmpty);
      // A migrated payload with no loop key defaults to looping on.
      expect(doc.loop, isTrue);
    });

    test('a v2 map payload round-trips unchanged through encode', () {
      final v2 = codec.encode(document())! as Map<String, Object?>;
      final again = codec.encode(v2)! as Map<String, Object?>;
      expect(again, v2);
    });

    test('null round-trips as null', () {
      expect(codec.encode(null), isNull);
      expect(codec.decode(null, 2), isNull);
    });
  });
}
