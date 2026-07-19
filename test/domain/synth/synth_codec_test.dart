import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/synth/fm_synth.dart';
import 'package:phi/domain/synth/synth_codec.dart';
import 'package:phi/domain/synth/synth_definition.dart';
import 'package:phi/domain/synth/va_synth.dart';

void main() {
  group('SynthCodec', () {
    const codec = SynthCodec();

    test('declares schema version 1', () {
      expect(codec.version, 1);
    });

    test('encodes a SynthDefinition to its tagged JSON map', () {
      final encoded = codec.encode(const VaSynth(voiceCount: 4));
      expect(encoded, isA<Map<String, Object?>>());
      expect((encoded! as Map<String, Object?>)['kind'], 'va');
    });

    test('encodes a raw map by normalising through the definition', () {
      // Extra keys are dropped; the round-trip normalises to the canonical map.
      final encoded = codec.encode(const {
        'kind': 'fm',
        'patchIndex': 3,
        'stray': 9,
      });
      expect(encoded, const FmSynth(patchIndex: 3).toJson());
    });

    test('decode returns a normalised map that rebuilds the definition', () {
      final decoded = codec.decode(const FmSynth(patchIndex: 2).toJson(), 1);
      expect(
        SynthDefinition.fromJson((decoded! as Map).cast<String, Object?>()),
        const FmSynth(patchIndex: 2),
      );
    });

    test('null round-trips as null', () {
      expect(codec.encode(null), isNull);
      expect(codec.decode(null, 1), isNull);
    });
  });
}
