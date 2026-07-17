import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/mix/mix_strip.dart';

void main() {
  group('MixStrip', () {
    test('round-trips through JSON', () {
      const strip = MixStrip(name: 'ch 1', voice: 3);
      expect(MixStrip.fromJson(strip.toJson()), strip);
    });

    test('toJson carries the display name and voice', () {
      expect(const MixStrip(name: 'drums', voice: 2).toJson(), {
        'name': 'drums',
        'voice': 2,
      });
    });

    test('fromJson fills defaults for a partial map', () {
      final strip = MixStrip.fromJson(const {});
      expect(strip.name, 'channel');
      expect(strip.voice, 1);
    });

    test('copyWith replaces only the given fields', () {
      const strip = MixStrip(name: 'pad', voice: 4);
      expect(strip.copyWith(voice: 5), const MixStrip(name: 'pad', voice: 5));
      expect(
        strip.copyWith(name: 'lead'),
        const MixStrip(name: 'lead', voice: 4),
      );
    });

    test('equality is by value', () {
      expect(
        const MixStrip(name: 'a', voice: 1),
        const MixStrip(name: 'a', voice: 1),
      );
      expect(
        const MixStrip(name: 'a', voice: 1),
        isNot(const MixStrip(name: 'a', voice: 2)),
      );
    });
  });
}
