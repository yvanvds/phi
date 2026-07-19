import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/synth/va_filter.dart';

void main() {
  group('VaFilter', () {
    test('round-trips through JSON', () {
      const filter = VaFilter(
        cutoff: 800.0,
        resonance: 0.7,
        keyTracking: 0.5,
        envAmount: 2.0,
        velAmount: 1.0,
      );
      expect(VaFilter.fromJson(filter.toJson()), filter);
    });

    test('fromJson fills defaults for a partial map', () {
      expect(VaFilter.fromJson(const {}), const VaFilter());
    });

    test('copyWith replaces only the given fields', () {
      const filter = VaFilter();
      expect(filter.copyWith(cutoff: 100.0).cutoff, 100.0);
      expect(filter.copyWith(cutoff: 100.0).resonance, filter.resonance);
    });

    test('equality and hashCode are by value', () {
      expect(const VaFilter(), const VaFilter());
      expect(const VaFilter().hashCode, const VaFilter().hashCode);
      expect(const VaFilter(resonance: 0.9), isNot(const VaFilter()));
    });
  });
}
