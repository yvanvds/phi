import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/mix/mix_strip_codec.dart';

void main() {
  group('MixStripCodec', () {
    const codec = MixStripCodec();

    test('declares schema version 1', () {
      expect(codec.version, 1);
    });

    test('encodes a MixStrip to its JSON map', () {
      expect(codec.encode(const MixStrip(name: 'drums', voice: 2)), {
        'name': 'drums',
        'voice': 2,
      });
    });

    test('encodes a raw map by normalising through MixStrip', () {
      // Extra keys are dropped; missing ones defaulted.
      expect(codec.encode(const {'name': 'pad', 'extra': 9}), {
        'name': 'pad',
        'voice': 1,
      });
    });

    test('decode returns a normalised map', () {
      expect(codec.decode(const {'name': 'lead', 'voice': 5}, 1), {
        'name': 'lead',
        'voice': 5,
      });
    });

    test('null round-trips as null', () {
      expect(codec.encode(null), isNull);
      expect(codec.decode(null, 1), isNull);
    });
  });
}
