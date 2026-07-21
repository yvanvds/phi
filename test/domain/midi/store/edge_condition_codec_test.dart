import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/graph/always_condition.dart';
import 'package:phi/domain/midi/graph/runtime_variable_condition.dart';
import 'package:phi/domain/midi/graph/state_match_condition.dart';
import 'package:phi/domain/midi/store/edge_condition_codec.dart';
import 'package:phi/domain/project/entity_address.dart';

void main() {
  const codec = EdgeConditionCodec();

  test('always condition round-trips', () {
    final decoded = codec.decode(codec.encode(const AlwaysCondition()));
    expect(decoded, isA<AlwaysCondition>());
  });

  test('state-match condition keeps its state address', () {
    final decoded = codec.decode(
      codec.encode(StateMatchCondition(EntityAddress.parse('state.break_'))),
    );
    expect(decoded, isA<StateMatchCondition>());
    expect((decoded as StateMatchCondition).state.format(), 'state.break_');
  });

  test('the state guard is written as the dotted address (issue #240)', () {
    final json = codec.encode(
      StateMatchCondition(EntityAddress.parse('state.verse')),
    );
    expect(json, {'type': 'state_match', 'state': 'state.verse'});
  });

  test('a state guard missing its address throws a FormatException', () {
    // The pre-#240 form persisted a canvas-local `stateId`; there is no compat
    // shim, so it fails loudly like any other corrupt guard.
    expect(
      () => codec.decode(const {'type': 'state_match', 'stateId': 's1'}),
      throwsFormatException,
    );
  });

  test('runtime-variable condition keeps its name + expected value', () {
    final decoded = codec.decode(
      codec.encode(
        const RuntimeVariableCondition(name: 'mode', expected: 'lead'),
      ),
    );
    expect(decoded, isA<RuntimeVariableCondition>());
    final c = decoded as RuntimeVariableCondition;
    expect(c.name, 'mode');
    expect(c.expected, 'lead');
  });

  test('an unknown condition type throws a FormatException', () {
    expect(() => codec.decode(const {'type': 'nope'}), throwsFormatException);
  });
}
