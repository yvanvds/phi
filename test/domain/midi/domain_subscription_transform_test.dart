import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_kind.dart';
import 'package:phi/domain/midi/transforms/domain_subscription_transform.dart';
import 'package:phi/domain/time_domains/time_domain.dart';
import 'package:phi/domain/time_domains/time_domain_registry.dart';

void main() {
  group('DomainSubscriptionTransform', () {
    const drum = TimeDomain(name: 'drum', tempo: 124);
    const input = [
      MidiNote(pitch: 60, start: 0.5, duration: 0.25, velocity: 0.7),
      MidiNote(pitch: 62, start: 1.0, duration: 0.5, velocity: 0.6, channel: 3),
    ];

    test('kind is time', () {
      const t = DomainSubscriptionTransform(
        domainName: 'drum',
        referenceTempo: 120,
        label: 'domain · drum',
      );
      expect(t.kind, MidiTransformKind.time);
    });

    test('identity when domain tempo equals the reference tempo', () {
      const t = DomainSubscriptionTransform(
        domainName: 'drum',
        referenceTempo: 124,
        label: 'domain · drum',
        domain: TimeDomain(name: 'drum', tempo: 124),
      );
      expect(t.scale, 1.0);
      expect(t.apply(input), input);
    });

    test('rescales beats by referenceTempo / domainTempo', () {
      const t = DomainSubscriptionTransform(
        domainName: 'drum',
        referenceTempo: 120,
        label: 'domain · drum',
        domain: drum,
      );
      const scale = 120 / 124;
      expect(t.scale, closeTo(scale, 1e-12));
      final out = t.apply(input);
      expect(out[0].start, closeTo(0.5 * scale, 1e-12));
      expect(out[0].duration, closeTo(0.25 * scale, 1e-12));
      expect(out[1].start, closeTo(1.0 * scale, 1e-12));
      expect(out[1].duration, closeTo(0.5 * scale, 1e-12));
    });

    test('locking to a faster domain compresses; a slower one stretches', () {
      const faster = DomainSubscriptionTransform(
        domainName: 'd',
        referenceTempo: 120,
        label: 'd',
        domain: TimeDomain(name: 'd', tempo: 240),
      );
      const slower = DomainSubscriptionTransform(
        domainName: 'd',
        referenceTempo: 120,
        label: 'd',
        domain: TimeDomain(name: 'd', tempo: 60),
      );
      expect(faster.scale, 0.5);
      expect(slower.scale, 2.0);
    });

    test('leaves pitch, velocity, and channel untouched', () {
      const t = DomainSubscriptionTransform(
        domainName: 'drum',
        referenceTempo: 120,
        label: 'domain · drum',
        domain: drum,
      );
      final out = t.apply(input);
      expect(out[1].pitch, 62);
      expect(out[1].velocity, 0.6);
      expect(out[1].channel, 3);
    });

    test('an unresolved domain is the identity', () {
      const t = DomainSubscriptionTransform(
        domainName: 'ghost',
        referenceTempo: 120,
        label: 'domain · ghost',
      );
      expect(t.domain, isNull);
      expect(t.scale, 1.0);
      expect(t.apply(input), input);
    });

    test('resolve() binds the domain found in the registry', () {
      final registry = TimeDomainRegistry(const [drum]);
      final t = DomainSubscriptionTransform.resolve(
        registry: registry,
        domainName: 'drum',
        referenceTempo: 120,
        label: 'domain · drum',
      );
      expect(t.domain, drum);
      expect(t.scale, closeTo(120 / 124, 1e-12));
    });

    test('resolve() leaves the domain null when the name is absent', () {
      final t = DomainSubscriptionTransform.resolve(
        registry: TimeDomainRegistry(const [drum]),
        domainName: 'pad',
        referenceTempo: 120,
        label: 'domain · pad',
      );
      expect(t.domain, isNull);
      expect(t.apply(input), input);
    });

    test('apply is pure — same input, same output, source untouched', () {
      const t = DomainSubscriptionTransform(
        domainName: 'drum',
        referenceTempo: 120,
        label: 'domain · drum',
        domain: drum,
      );
      final first = t.apply(input);
      final second = t.apply(input);
      expect(first.map((n) => n.start), second.map((n) => n.start));
      // Original notes are not mutated.
      expect(input[0].start, 0.5);
    });

    test('empty input yields empty output', () {
      const t = DomainSubscriptionTransform(
        domainName: 'drum',
        referenceTempo: 120,
        label: 'domain · drum',
        domain: drum,
      );
      expect(t.apply(const []), isEmpty);
    });

    test('copyWith flips active and renames, keeping domain binding', () {
      const t = DomainSubscriptionTransform(
        domainName: 'drum',
        referenceTempo: 120,
        label: 'domain · drum',
        domain: drum,
      );
      final flipped = t.copyWith(active: false, label: 'domain · drum @ 124');
      expect(flipped.active, isFalse);
      expect(flipped.label, 'domain · drum @ 124');
      expect(flipped.domainName, 'drum');
      expect(flipped.referenceTempo, 120);
      expect(flipped.domain, drum);
      expect(flipped.scale, closeTo(120 / 124, 1e-12));
    });

    test('rejects a non-positive reference tempo', () {
      expect(
        () => DomainSubscriptionTransform(
          domainName: 'drum',
          referenceTempo: 0,
          label: 'x',
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
