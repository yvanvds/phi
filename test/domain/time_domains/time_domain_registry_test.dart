import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/time_domains/time_domain.dart';
import 'package:phi/domain/time_domains/time_domain_registry.dart';

void main() {
  group('TimeDomainRegistry', () {
    const drum = TimeDomain(name: 'drum', tempo: 128);
    const pad = TimeDomain(name: 'pad', tempo: 90);

    test('is empty by default', () {
      final registry = TimeDomainRegistry();
      expect(registry.length, 0);
      expect(registry.domains, isEmpty);
      expect(registry.resolve('drum'), isNull);
      expect(registry.contains('drum'), isFalse);
    });

    test('resolves a domain by name', () {
      final registry = TimeDomainRegistry([drum, pad]);
      expect(registry.resolve('drum'), drum);
      expect(registry.resolve('pad'), pad);
      expect(registry.contains('drum'), isTrue);
      expect(registry.names, containsAll(['drum', 'pad']));
    });

    test('returns null for an unknown name', () {
      final registry = TimeDomainRegistry([drum]);
      expect(registry.resolve('missing'), isNull);
      expect(registry.contains('missing'), isFalse);
    });

    test('later entries win when two share a name', () {
      const fastDrum = TimeDomain(name: 'drum', tempo: 174);
      final registry = TimeDomainRegistry([drum, fastDrum]);
      expect(registry.length, 1);
      expect(registry.resolve('drum'), fastDrum);
    });

    test('add returns a new registry and leaves the original untouched', () {
      final base = TimeDomainRegistry([drum]);
      final extended = base.add(pad);
      expect(base.contains('pad'), isFalse);
      expect(extended.contains('pad'), isTrue);
      expect(extended.resolve('drum'), drum);
    });

    test('add overrides a domain sharing its name', () {
      const fastDrum = TimeDomain(name: 'drum', tempo: 174);
      final registry = TimeDomainRegistry([drum]).add(fastDrum);
      expect(registry.length, 1);
      expect(registry.resolve('drum'), fastDrum);
    });

    test('remove returns a new registry without the named domain', () {
      final base = TimeDomainRegistry([drum, pad]);
      final trimmed = base.remove('drum');
      expect(base.contains('drum'), isTrue);
      expect(trimmed.contains('drum'), isFalse);
      expect(trimmed.resolve('pad'), pad);
    });

    test('remove of an absent name returns an equal registry', () {
      final base = TimeDomainRegistry([drum]);
      expect(base.remove('missing'), base);
    });

    test('equality is value-based and order-independent', () {
      final a = TimeDomainRegistry([drum, pad]);
      final b = TimeDomainRegistry([pad, drum]);
      final c = TimeDomainRegistry([drum]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
