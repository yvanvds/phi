import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/mix/mix_send.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/mix/mix_strip_codec.dart';
import 'package:phi/domain/project/entity_address.dart';

void main() {
  EntityAddress mix(String dotted) => EntityAddress.parse('mix.$dotted');

  group('MixStripCodec', () {
    const codec = MixStripCodec();

    test('declares schema version 3 (return + sends, no name; #166)', () {
      expect(codec.version, 3);
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
        }, 3),
        {
          'voice': 5,
          'volume': 0.8,
          'muted': false,
          'soloed': true,
          'return': false,
          'sends': <Object?>[],
        },
      );
    });

    test(
      'migrates a v2 payload forward, dropping name and defaulting sends',
      () {
        // A file written before #166 carried name + live state at version 2.
        expect(
          codec.decode(const {
            'name': 'bass',
            'voice': 4,
            'volume': 0.6,
            'muted': false,
            'soloed': false,
          }, 2),
          {
            'voice': 4,
            'volume': 0.6,
            'muted': false,
            'soloed': false,
            'return': false,
            'sends': <Object?>[],
          },
        );
      },
    );

    test('null round-trips as null', () {
      expect(codec.encode(null), isNull);
      expect(codec.decode(null, 3), isNull);
    });
  });
}
