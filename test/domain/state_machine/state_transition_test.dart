import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/state_machine/state_transition.dart';

/// The immutable canvas edge value the registry-backed controller derives
/// from the source state's persisted transition specs (issue #241).
void main() {
  final intro = EntityAddress.parse('state.intro');
  final verse = EntityAddress.parse('state.verse');

  group('StateTransition', () {
    test('equality is on (source, target) only — armed/fireOn are display', () {
      final a = StateTransition(source: intro, target: verse);
      final b = StateTransition(
        source: intro,
        target: verse,
        armed: true,
        fireOn: 'timed',
        triggerKind: 'timed',
      );

      // Same edge: this is what lets the controller key its arm set by
      // endpoints and remap an arm in place across a rename.
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(StateTransition(source: verse, target: intro)));
    });

    test('copyWith replaces the display fields and keeps the endpoints', () {
      final t = StateTransition(source: intro, target: verse);
      final armed = t.copyWith(
        armed: true,
        fireOn: 'code',
        triggerKind: 'code',
      );

      expect(armed.source, intro);
      expect(armed.target, verse);
      expect(armed.armed, isTrue);
      expect(armed.fireOn, 'code');
      expect(armed.triggerKind, 'code');
      // Defaults: manual, not armed.
      expect(t.armed, isFalse);
      expect(t.fireOn, 'manual');
      expect(t.triggerKind, 'manual');
    });
  });
}
