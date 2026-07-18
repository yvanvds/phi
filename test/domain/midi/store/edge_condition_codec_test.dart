import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/graph/always_condition.dart';
import 'package:phi/domain/midi/graph/runtime_variable_condition.dart';
import 'package:phi/domain/midi/graph/state_match_condition.dart';
import 'package:phi/domain/midi/store/edge_condition_codec.dart';
import 'package:phi/domain/state_machine/performance_state_id.dart';

void main() {
  const codec = EdgeConditionCodec();

  test('always condition round-trips', () {
    final decoded = codec.decode(codec.encode(const AlwaysCondition()));
    expect(decoded, isA<AlwaysCondition>());
  });

  test('state-match condition keeps its state id', () {
    final decoded = codec.decode(
      codec.encode(const StateMatchCondition(PerformanceStateId('break'))),
    );
    expect(decoded, isA<StateMatchCondition>());
    expect((decoded as StateMatchCondition).stateId.value, 'break');
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
