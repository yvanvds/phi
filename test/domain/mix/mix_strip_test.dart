import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/mix/mix_strip.dart';

void main() {
  group('MixStrip', () {
    test('round-trips through JSON', () {
      const strip = MixStrip(
        name: 'ch 1',
        voice: 3,
        volume: 0.42,
        muted: true,
        soloed: true,
      );
      expect(MixStrip.fromJson(strip.toJson()), strip);
    });

    test('toJson carries identity and live mix state', () {
      expect(
        const MixStrip(
          name: 'drums',
          voice: 2,
          volume: 0.5,
          muted: true,
          soloed: false,
        ).toJson(),
        {
          'name': 'drums',
          'voice': 2,
          'volume': 0.5,
          'muted': true,
          'soloed': false,
        },
      );
    });

    test('fromJson fills defaults for a partial map', () {
      final strip = MixStrip.fromJson(const {});
      expect(strip.name, 'channel');
      expect(strip.voice, 1);
      expect(strip.volume, 1.0);
      expect(strip.muted, isFalse);
      expect(strip.soloed, isFalse);
    });

    test('fromJson defaults the live state for a v1 (identity-only) map', () {
      // A pre-#136 file carried only name + voice.
      final strip = MixStrip.fromJson(const {'name': 'bass', 'voice': 4});
      expect(strip, const MixStrip(name: 'bass', voice: 4));
      expect(strip.volume, 1.0);
      expect(strip.muted, isFalse);
      expect(strip.soloed, isFalse);
    });

    test('copyWith replaces only the given fields', () {
      const strip = MixStrip(name: 'pad', voice: 4);
      expect(strip.copyWith(voice: 5), const MixStrip(name: 'pad', voice: 5));
      expect(
        strip.copyWith(name: 'lead'),
        const MixStrip(name: 'lead', voice: 4),
      );
      expect(
        strip.copyWith(volume: 0.3, muted: true, soloed: true),
        const MixStrip(
          name: 'pad',
          voice: 4,
          volume: 0.3,
          muted: true,
          soloed: true,
        ),
      );
    });

    test('equality is by value across every field', () {
      expect(
        const MixStrip(name: 'a', voice: 1),
        const MixStrip(name: 'a', voice: 1),
      );
      expect(
        const MixStrip(name: 'a', voice: 1),
        isNot(const MixStrip(name: 'a', voice: 2)),
      );
      expect(
        const MixStrip(name: 'a', voice: 1, volume: 0.5),
        isNot(const MixStrip(name: 'a', voice: 1)),
      );
      expect(
        const MixStrip(name: 'a', voice: 1, muted: true),
        isNot(const MixStrip(name: 'a', voice: 1)),
      );
      expect(
        const MixStrip(name: 'a', voice: 1, soloed: true),
        isNot(const MixStrip(name: 'a', voice: 1)),
      );
    });
  });
}
