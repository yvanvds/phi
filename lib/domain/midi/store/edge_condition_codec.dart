import '../../project/entity_address.dart';
import '../graph/always_condition.dart';
import '../graph/edge_condition.dart';
import '../graph/runtime_variable_condition.dart';
import '../graph/state_match_condition.dart';

/// (De)serialises a [MidiTransformGraph] edge's [EdgeCondition] — the guard that
/// decides whether notes flow down a branch (issue #135's graph-persistence
/// half).
///
/// Three guards exist today: [AlwaysCondition] (unconditional), the
/// [StateMatchCondition] on a live state-machine state, and the
/// [RuntimeVariableCondition] on a named runtime variable. Each is tagged with a
/// stable `type` string — a frozen wire contract independent of the Dart class
/// name. A [StateMatchCondition] persists the guarded `state.` entity address
/// in dotted form (issue #240) — the same name used in live code — so a
/// reloaded guard re-binds by address, with no remapping step. The pre-#240
/// `stateId` form is not read back (no compat shim, per the established
/// stance): decoding it fails loudly like any other corrupt guard.
class EdgeConditionCodec {
  /// A const codec — it holds no state.
  const EdgeConditionCodec();

  /// Flattens [condition] to a JSON-compatible map tagged with its `type`.
  Map<String, Object?> encode(EdgeCondition condition) => switch (condition) {
    AlwaysCondition() => const {'type': 'always'},
    final StateMatchCondition c => {
      'type': 'state_match',
      'state': c.state.format(),
    },
    final RuntimeVariableCondition c => {
      'type': 'runtime_variable',
      'name': c.name,
      'expected': c.expected,
    },
    _ => throw ArgumentError.value(
      condition,
      'condition',
      'no EdgeConditionCodec case for ${condition.runtimeType}',
    ),
  };

  /// Rebuilds an [EdgeCondition] from the map [encode] produced. Throws a
  /// [FormatException] on an unknown `type` — or a missing/malformed guard
  /// address — so a corrupt clip file fails loudly.
  EdgeCondition decode(Map<String, Object?> json) {
    switch (json['type']) {
      case 'always':
        return const AlwaysCondition();
      case 'state_match':
        return StateMatchCondition(
          EntityAddress.parse(json['state'] as String? ?? ''),
        );
      case 'runtime_variable':
        return RuntimeVariableCondition(
          name: json['name'] as String? ?? '',
          expected: json['expected'],
        );
      default:
        throw FormatException('Unknown edge condition: "${json['type']}".');
    }
  }
}
