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
        label: 'domain · drum',
      );
      expect(t.kind, MidiTransformKind.time);
    });

    test('boundTempo is the resolved domain tempo', () {
      const t = DomainSubscriptionTransform(
        domainName: 'drum',
        label: 'domain · drum',
        domain: drum,
      );
      expect(t.boundTempo, 124);
    });

    test('apply is the identity — a subscription binds a clock, not notes', () {
      const t = DomainSubscriptionTransform(
        domainName: 'drum',
        label: 'domain · drum',
        domain: drum,
      );
      // Same instance back: no start/duration rescale, no copy.
      expect(identical(t.apply(input), input), isTrue);
      expect(t.apply(input), input);
    });

    test('faster and slower domains both leave note times untouched', () {
      const faster = DomainSubscriptionTransform(
        domainName: 'd',
        label: 'd',
        domain: TimeDomain(name: 'd', tempo: 240),
      );
      const slower = DomainSubscriptionTransform(
        domainName: 'd',
        label: 'd',
        domain: TimeDomain(name: 'd', tempo: 60),
      );
      // The tempo the clock would run at differs, but the beats do not move.
      expect(faster.boundTempo, 240);
      expect(slower.boundTempo, 60);
      expect(faster.apply(input), input);
      expect(slower.apply(input), input);
    });

    test('leaves pitch, velocity, and channel untouched', () {
      const t = DomainSubscriptionTransform(
        domainName: 'drum',
        label: 'domain · drum',
        domain: drum,
      );
      final out = t.apply(input);
      expect(out[1].pitch, 62);
      expect(out[1].velocity, 0.6);
      expect(out[1].channel, 3);
    });

    test('an unresolved domain binds nothing (boundTempo is null)', () {
      const t = DomainSubscriptionTransform(
        domainName: 'ghost',
        label: 'domain · ghost',
      );
      expect(t.domain, isNull);
      expect(t.boundTempo, isNull);
      expect(t.apply(input), input);
    });

    test('resolve() binds the domain found in the registry', () {
      final registry = TimeDomainRegistry(const [drum]);
      final t = DomainSubscriptionTransform.resolve(
        registry: registry,
        domainName: 'drum',
        label: 'domain · drum',
      );
      expect(t.domain, drum);
      expect(t.boundTempo, 124);
    });

    test('resolve() leaves the domain null when the name is absent', () {
      final t = DomainSubscriptionTransform.resolve(
        registry: TimeDomainRegistry(const [drum]),
        domainName: 'pad',
        label: 'domain · pad',
      );
      expect(t.domain, isNull);
      expect(t.boundTempo, isNull);
      expect(t.apply(input), input);
    });

    test('empty input yields empty output', () {
      const t = DomainSubscriptionTransform(
        domainName: 'drum',
        label: 'domain · drum',
        domain: drum,
      );
      expect(t.apply(const []), isEmpty);
    });

    test('copyWith flips active and renames, keeping the domain binding', () {
      const t = DomainSubscriptionTransform(
        domainName: 'drum',
        label: 'domain · drum',
        domain: drum,
      );
      final flipped = t.copyWith(active: false, label: 'domain · drum @ 124');
      expect(flipped.active, isFalse);
      expect(flipped.label, 'domain · drum @ 124');
      expect(flipped.domainName, 'drum');
      expect(flipped.domain, drum);
      expect(flipped.boundTempo, 124);
    });
  });
}
