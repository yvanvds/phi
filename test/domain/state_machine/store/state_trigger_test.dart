import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/state_machine/store/state_trigger.dart';

void main() {
  final drum = EntityAddress.parse('domain.drum');
  final synths = EntityAddress.parse('domain.synths');

  group('StateTrigger JSON round-trip', () {
    test('manual', () {
      const trigger = ManualTrigger();
      expect(StateTrigger.fromJson(trigger.toJson()), trigger);
      expect(trigger.toJson(), {'kind': 'manual'});
    });

    test('code', () {
      const trigger = CodeTrigger();
      expect(StateTrigger.fromJson(trigger.toJson()), trigger);
      expect(trigger.toJson(), {'kind': 'code'});
    });

    test('timed', () {
      final trigger = TimedTrigger(beats: 16, domain: drum);
      expect(StateTrigger.fromJson(trigger.toJson()), trigger);
      expect(trigger.toJson(), {
        'kind': 'timed',
        'beats': 16.0,
        'domain': 'domain.drum',
      });
    });

    test('variable', () {
      const trigger = VariableTrigger(name: 'section', value: 'a');
      expect(StateTrigger.fromJson(trigger.toJson()), trigger);
      expect(trigger.toJson(), {
        'kind': 'variable',
        'name': 'section',
        'value': 'a',
      });
    });
  });

  group('StateTrigger corrupt input', () {
    test('an unknown kind throws', () {
      expect(
        () => StateTrigger.fromJson(const {'kind': 'sensor'}),
        throwsFormatException,
      );
    });

    test('a timed trigger without beats or domain throws', () {
      expect(
        () => StateTrigger.fromJson(const {'kind': 'timed', 'beats': 4}),
        throwsFormatException,
      );
      expect(
        () => StateTrigger.fromJson(const {
          'kind': 'timed',
          'domain': 'domain.drum',
        }),
        throwsFormatException,
      );
    });

    test('a variable trigger without name or value throws', () {
      expect(
        () => StateTrigger.fromJson(const {'kind': 'variable', 'name': 'x'}),
        throwsFormatException,
      );
    });
  });

  group('StateTrigger references', () {
    test('only the timed trigger references an entity — its domain', () {
      expect(const ManualTrigger().references, isEmpty);
      expect(const CodeTrigger().references, isEmpty);
      expect(
        const VariableTrigger(name: 'section', value: 'a').references,
        isEmpty,
      );
      expect(TimedTrigger(beats: 8, domain: drum).references, {drum});
    });

    test('withReferenceUpdated repoints a timed trigger domain', () {
      final trigger = TimedTrigger(beats: 8, domain: drum);
      final repointed = trigger.withReferenceUpdated(drum, synths);
      expect(repointed, TimedTrigger(beats: 8, domain: synths));
      // The inverse restores the original — undo round-trips.
      expect(repointed.withReferenceUpdated(synths, drum), trigger);
      // A non-matching address is the identity.
      expect(
        identical(trigger.withReferenceUpdated(synths, drum), trigger),
        isTrue,
      );
    });
  });
}
