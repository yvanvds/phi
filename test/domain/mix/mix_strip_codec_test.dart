import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/mix/mix_strip_codec.dart';

void main() {
  group('MixStripCodec', () {
    const codec = MixStripCodec();

    test('declares schema version 2 (live mix state added in #136)', () {
      expect(codec.version, 2);
    });

    test('encodes a MixStrip to its JSON map', () {
      expect(
        codec.encode(
          const MixStrip(
            name: 'drums',
            voice: 2,
            volume: 0.5,
            muted: true,
            soloed: false,
          ),
        ),
        {
          'name': 'drums',
          'voice': 2,
          'volume': 0.5,
          'muted': true,
          'soloed': false,
        },
      );
    });

    test('encodes a raw map by normalising through MixStrip', () {
      // Extra keys are dropped; missing ones defaulted.
      expect(codec.encode(const {'name': 'pad', 'extra': 9}), {
        'name': 'pad',
        'voice': 1,
        'volume': 1.0,
        'muted': false,
        'soloed': false,
      });
    });

    test('decode returns a normalised map', () {
      expect(
        codec.decode(const {
          'name': 'lead',
          'voice': 5,
          'volume': 0.8,
          'muted': false,
          'soloed': true,
        }, 2),
        {
          'name': 'lead',
          'voice': 5,
          'volume': 0.8,
          'muted': false,
          'soloed': true,
        },
      );
    });

    test('migrates a v1 (identity-only) payload forward with defaults', () {
      // A file written before #136 carried only name + voice at version 1.
      expect(codec.decode(const {'name': 'bass', 'voice': 4}, 1), {
        'name': 'bass',
        'voice': 4,
        'volume': 1.0,
        'muted': false,
        'soloed': false,
      });
    });

    test('null round-trips as null', () {
      expect(codec.encode(null), isNull);
      expect(codec.decode(null, 2), isNull);
    });
  });
}
