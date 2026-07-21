import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/state_machine/store/state_transition_spec.dart';
import 'package:phi/domain/state_machine/store/state_trigger.dart';

void main() {
  final verse = EntityAddress.parse('state.verse');
  final chorus = EntityAddress.parse('state.chorus');
  final drum = EntityAddress.parse('domain.drum');

  group('StateTransitionSpec JSON round-trip', () {
    test('a manual transition with a label round-trips', () {
      final spec = StateTransitionSpec(to: verse, label: 'drop');
      expect(StateTransitionSpec.fromJson(spec.toJson()), spec);
      expect(spec.toJson(), {
        'to': 'state.verse',
        'trigger': {'kind': 'manual'},
        'label': 'drop',
      });
    });

    test('a label-less transition omits the key and round-trips', () {
      final spec = StateTransitionSpec(to: verse);
      expect(spec.toJson().containsKey('label'), isFalse);
      expect(StateTransitionSpec.fromJson(spec.toJson()), spec);
    });

    test('a timed transition keeps its trigger', () {
      final spec = StateTransitionSpec(
        to: verse,
        trigger: TimedTrigger(beats: 16, domain: drum),
      );
      expect(StateTransitionSpec.fromJson(spec.toJson()), spec);
    });

    test('a missing trigger decodes as manual', () {
      final spec = StateTransitionSpec.fromJson(const {'to': 'state.verse'});
      expect(spec.trigger, const ManualTrigger());
    });

    test('a missing target throws', () {
      expect(
        () => StateTransitionSpec.fromJson(const {'label': 'x'}),
        throwsFormatException,
      );
    });
  });

  group('StateTransitionSpec references', () {
    test('references its target and the trigger domain', () {
      final spec = StateTransitionSpec(
        to: verse,
        trigger: TimedTrigger(beats: 16, domain: drum),
      );
      expect(spec.references, {verse, drum});
    });

    test('withReferenceUpdated repoints the target and round-trips', () {
      final spec = StateTransitionSpec(to: verse, label: 'drop');
      final repointed = spec.withReferenceUpdated(verse, chorus);
      expect(repointed.to, chorus);
      expect(repointed.label, 'drop');
      expect(repointed.withReferenceUpdated(chorus, verse), spec);
    });

    test('withReferenceUpdated repoints a trigger domain', () {
      final other = EntityAddress.parse('domain.synths');
      final spec = StateTransitionSpec(
        to: verse,
        trigger: TimedTrigger(beats: 16, domain: drum),
      );
      final repointed = spec.withReferenceUpdated(drum, other);
      expect(repointed.to, verse);
      expect(repointed.trigger, TimedTrigger(beats: 16, domain: other));
    });

    test('an unrelated address is the identity', () {
      final spec = StateTransitionSpec(to: verse);
      expect(identical(spec.withReferenceUpdated(chorus, verse), spec), isTrue);
    });
  });
}
