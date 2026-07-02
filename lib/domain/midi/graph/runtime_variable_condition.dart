import 'edge_condition.dart';
import 'graph_eval_context.dart';

/// Opens the edge when a named runtime variable equals an expected value.
///
/// The second context source vision §3.7 names, alongside
/// [StateMatchCondition]. Comparison is by `==` against
/// [GraphEvalContext.variable], so an unset variable (`null`) only matches a
/// condition whose [expected] is itself `null`.
class RuntimeVariableCondition extends EdgeCondition {
  const RuntimeVariableCondition({required this.name, required this.expected});

  /// The runtime variable to read from the context.
  final String name;

  /// The value [name] must equal for the edge to open.
  final Object? expected;

  @override
  bool isSatisfiedBy(GraphEvalContext context) =>
      context.variable(name) == expected;

  @override
  String get label => '$name = $expected';

  @override
  bool operator ==(Object other) =>
      other is RuntimeVariableCondition &&
      other.name == name &&
      other.expected == expected;

  @override
  int get hashCode => Object.hash(name, expected);
}
