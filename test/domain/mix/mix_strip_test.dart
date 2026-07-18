import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/mix/mix_send.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/project/entity_address.dart';

void main() {
  EntityAddress mix(String dotted) => EntityAddress.parse('mix.$dotted');

  group('MixStrip', () {
    test('round-trips through JSON', () {
      final strip = MixStrip(
        voice: 3,
        volume: 0.42,
        muted: true,
        soloed: true,
        isReturn: true,
        sends: [MixSend(to: mix('verb'), level: 0.4)],
      );
      expect(MixStrip.fromJson(strip.toJson()), strip);
    });

    test('toJson carries the mix state, return flag and sends — no name', () {
      expect(
        MixStrip(
          voice: 2,
          volume: 0.5,
          muted: true,
          sends: [MixSend(to: mix('verb'), level: 0.3, preFader: true)],
        ).toJson(),
        {
          'voice': 2,
          'volume': 0.5,
          'muted': true,
          'soloed': false,
          'return': false,
          'sends': [
            {'to': 'mix.verb', 'level': 0.3, 'preFader': true},
          ],
        },
      );
    });

    test('fromJson fills defaults for a partial map', () {
      final strip = MixStrip.fromJson(const {});
      expect(strip.voice, 1);
      expect(strip.volume, 1.0);
      expect(strip.muted, isFalse);
      expect(strip.soloed, isFalse);
      expect(strip.isReturn, isFalse);
      expect(strip.sends, isEmpty);
    });

    test('fromJson ignores a legacy display name (one-name re-alignment)', () {
      // A pre-#166 payload carried a free-form `name`; it is simply not read.
      final strip = MixStrip.fromJson(const {'name': 'lead synth', 'voice': 4});
      expect(strip, const MixStrip(voice: 4));
    });

    test('fromJson defaults return + sends for a v2 (pre-#166) map', () {
      final strip = MixStrip.fromJson(const {
        'voice': 4,
        'volume': 0.5,
        'muted': false,
        'soloed': false,
      });
      expect(strip.isReturn, isFalse);
      expect(strip.sends, isEmpty);
    });

    test('copyWith replaces only the given fields', () {
      const strip = MixStrip(voice: 4);
      expect(strip.copyWith(voice: 5), const MixStrip(voice: 5));
      expect(
        strip.copyWith(isReturn: true),
        const MixStrip(voice: 4, isReturn: true),
      );
      expect(
        strip.copyWith(volume: 0.3, muted: true, soloed: true),
        const MixStrip(voice: 4, volume: 0.3, muted: true, soloed: true),
      );
    });

    test('equality is by value across every field including sends', () {
      expect(const MixStrip(voice: 1), const MixStrip(voice: 1));
      expect(const MixStrip(voice: 1), isNot(const MixStrip(voice: 2)));
      expect(
        const MixStrip(voice: 1, volume: 0.5),
        isNot(const MixStrip(voice: 1)),
      );
      expect(
        const MixStrip(voice: 1, isReturn: true),
        isNot(const MixStrip(voice: 1)),
      );
      expect(
        MixStrip(voice: 1, sends: [MixSend(to: mix('verb'))]),
        MixStrip(voice: 1, sends: [MixSend(to: mix('verb'))]),
      );
      expect(
        MixStrip(voice: 1, sends: [MixSend(to: mix('verb'))]),
        isNot(MixStrip(voice: 1, sends: [MixSend(to: mix('echo'))])),
      );
    });

    group('as a ReferenceSource', () {
      test('references are the send targets', () {
        final strip = MixStrip(
          voice: 1,
          sends: [
            MixSend(to: mix('verb')),
            MixSend(to: mix('echo')),
          ],
        );
        expect(strip.references, {mix('verb'), mix('echo')});
      });

      test('a strip with no sends references nothing', () {
        expect(const MixStrip(voice: 1).references, isEmpty);
      });

      test('withReferenceUpdated repoints every matching send', () {
        final strip = MixStrip(
          voice: 1,
          sends: [
            MixSend(to: mix('verb'), level: 0.4),
            MixSend(to: mix('echo')),
          ],
        );

        final rewritten = strip.withReferenceUpdated(
          mix('verb'),
          mix('reverb'),
        );

        expect(rewritten.sends.first.to, mix('reverb'));
        expect(rewritten.sends.first.level, 0.4); // other fields untouched
        expect(rewritten.sends[1].to, mix('echo')); // unrelated send unchanged
        expect(rewritten.references, {mix('reverb'), mix('echo')});
      });

      test('applying the inverse rewrite restores the original (undo)', () {
        final strip = MixStrip(voice: 1, sends: [MixSend(to: mix('verb'))]);
        final there = strip.withReferenceUpdated(mix('verb'), mix('reverb'));
        final back = there.withReferenceUpdated(mix('reverb'), mix('verb'));
        expect(back, strip);
      });
    });
  });
}
