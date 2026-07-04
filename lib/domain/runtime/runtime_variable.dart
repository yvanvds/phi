/// A named runtime variable the performance exposes to the MIDI transform
/// graph — the second of vision §3.7's two context sources, alongside the live
/// state machine.
///
/// A variable is an enumerated choice: a [name], a fixed set of candidate
/// [values], and the one that is [current]. Values are **strings** — the value
/// type story settled for now (issue #78): strings are stable, hashable, and
/// compare cleanly by `==`, which is exactly what [RuntimeVariableCondition]
/// needs. Enumerating the candidates (rather than free text) lets the edge
/// condition picker offer `var · name = value` choices instead of a blind text
/// field, and guarantees a guard can only ever name a value the variable can
/// actually take.
///
/// The definition ([name] + [values]) is immutable; only [current] moves, and
/// only through [RuntimeVariableRegistry.setValue] so a value change notifies
/// the one place the graph listens.
class RuntimeVariable {
  /// Build a variable named [name] over the candidate [values]. Duplicate
  /// values are dropped (first occurrence wins) and [values] must be non-empty.
  /// [current] defaults to the first candidate; a [current] outside [values]
  /// falls back to the first, so a variable is never in an impossible state.
  RuntimeVariable({
    required this.name,
    required List<String> values,
    String? current,
  }) : assert(values.isNotEmpty, 'a runtime variable needs at least one value'),
       values = List.unmodifiable(_dedupe(values)) {
    final candidates = this.values;
    _current = (current != null && candidates.contains(current))
        ? current
        : candidates.first;
  }

  /// The variable's name — its key in the registry and in
  /// [GraphEvalContext.variables].
  final String name;

  /// The candidate values, in definition order with duplicates removed. Always
  /// non-empty. The picker offers these; [current] is always one of them.
  final List<String> values;

  late String _current;

  /// The value the variable currently holds — always one of [values]. Read by
  /// the registry's snapshot; set only via [RuntimeVariableRegistry.setValue].
  String get current => _current;

  /// Overwrite [current]. Internal to the registry so a value change always
  /// travels through the notifying path. Returns whether the value changed
  /// (a no-op set, or a [value] outside [values], returns `false`).
  bool setCurrent(String value) {
    if (value == _current || !values.contains(value)) return false;
    _current = value;
    return true;
  }

  static List<String> _dedupe(List<String> values) {
    final seen = <String>{};
    return [
      for (final v in values)
        if (seen.add(v)) v,
    ];
  }
}
