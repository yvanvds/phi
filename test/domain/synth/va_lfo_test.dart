import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/synth/lfo_type.dart';
import 'package:phi/domain/synth/va_lfo.dart';

void main() {
  group('VaLfo', () {
    test('round-trips through JSON across every type', () {
      for (final type in LfoType.values) {
        final lfo = VaLfo(
          type: type,
          rate: 4.5,
          toPitch: 2.0,
          toCutoff: 1.5,
          toWavetable: 0.4,
        );
        expect(VaLfo.fromJson(lfo.toJson()), lfo);
      }
    });

    test('toJson serialises the type by name', () {
      expect(const VaLfo(type: LfoType.square).toJson()['type'], 'square');
    });

    test('fromJson defaults an unknown type back to none', () {
      expect(VaLfo.fromJson(const {'type': 'chaos'}).type, LfoType.none);
    });

    test('fromJson fills defaults for a partial map', () {
      expect(VaLfo.fromJson(const {}), const VaLfo());
    });

    test('equality is by value', () {
      expect(const VaLfo(), const VaLfo());
      expect(const VaLfo(rate: 9.0), isNot(const VaLfo()));
    });
  });
}
