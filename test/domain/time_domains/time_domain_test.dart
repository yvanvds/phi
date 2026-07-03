import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/time_domains/time_domain.dart';

void main() {
  group('TimeDomain', () {
    test('carries a name and a BPM tempo', () {
      const d = TimeDomain(name: 'drum', tempo: 128);
      expect(d.name, 'drum');
      expect(d.tempo, 128);
    });

    test('rejects a non-positive tempo', () {
      expect(
        () => TimeDomain(name: 'drum', tempo: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => TimeDomain(name: 'drum', tempo: -1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('copyWith replaces one field, keeps the rest', () {
      const d = TimeDomain(name: 'drum', tempo: 120);
      expect(d.copyWith(tempo: 90), const TimeDomain(name: 'drum', tempo: 90));
      expect(
        d.copyWith(name: 'pad'),
        const TimeDomain(name: 'pad', tempo: 120),
      );
    });

    test('equality and hashCode are value-based', () {
      const a = TimeDomain(name: 'drum', tempo: 120);
      const b = TimeDomain(name: 'drum', tempo: 120);
      const differentTempo = TimeDomain(name: 'drum', tempo: 121);
      const differentName = TimeDomain(name: 'pad', tempo: 120);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(differentTempo));
      expect(a, isNot(differentName));
    });
  });
}
