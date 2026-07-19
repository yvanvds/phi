import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/mix/mix_send.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/mix/mix_strip_codec.dart';
import 'package:phi/domain/project/entity_address.dart';

void main() {
  EntityAddress mix(String dotted) => EntityAddress.parse('mix.$dotted');

  group('MixStripCodec', () {
    const codec = MixStripCodec();

    test('declares schema version 4 (adds inserts; #204)', () {
      expect(codec.version, 4);
    });

    test('encodes a MixStrip to its JSON map', () {
      expect(
        codec.encode(
          MixStrip(
            voice: 2,
            volume: 0.5,
            muted: true,
            isReturn: true,
            sends: [MixSend(to: mix('verb'), level: 0.3)],
            inserts: [EntityAddress.parse('fx.big_delay')],
          ),
        ),
        {
          'voice': 2,
          'volume': 0.5,
          'muted': true,
          'soloed': false,
          'return': true,
          'sends': [
            {'to': 'mix.verb', 'level': 0.3, 'preFader': false},
          ],
          'inserts': ['fx.big_delay'],
        },
      );
    });

    test('encodes a raw map by normalising through MixStrip', () {
      // Extra keys — including a legacy `name` — are dropped; missing defaulted.
      expect(codec.encode(const {'name': 'pad', 'voice': 1, 'extra': 9}), {
        'voice': 1,
        'volume': 1.0,
        'muted': false,
        'soloed': false,
        'return': false,
        'sends': <Object?>[],
        'inserts': <Object?>[],
      });
    });

    test('decode returns a normalised map', () {
      expect(
        codec.decode(const {
          'voice': 5,
          'volume': 0.8,
          'muted': false,
          'soloed': true,
          'return': false,
          'sends': <Object?>[],
          'inserts': <Object?>[],
        }, 4),
        {
          'voice': 5,
          'volume': 0.8,
          'muted': false,
          'soloed': true,
          'return': false,
          'sends': <Object?>[],
          'inserts': <Object?>[],
        },
      );
    });

    test('migrates a v3 payload forward, defaulting the inserts chain', () {
      // A file written before #204 carried return + sends at version 3.
      expect(
        codec.decode(const {
          'voice': 4,
          'volume': 0.6,
          'muted': false,
          'soloed': false,
          'return': false,
          'sends': <Object?>[],
        }, 3),
        {
          'voice': 4,
          'volume': 0.6,
          'muted': false,
          'soloed': false,
          'return': false,
          'sends': <Object?>[],
          'inserts': <Object?>[],
        },
      );
    });

    test('null round-trips as null', () {
      expect(codec.encode(null), isNull);
      expect(codec.decode(null, 4), isNull);
    });
  });
}
