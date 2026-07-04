import 'package:flutter/foundation.dart';

import 'runtime_variable.dart';

/// The live store of the performance's [RuntimeVariable]s — the registry that
/// backs [RuntimeVariableCondition] (issue #78).
///
/// This closes the loop the node-and-cable editor left open (issue #65): the
/// edge condition picker reads [variables] to offer real `var · name = value`
/// guards, and the MIDI graph is fed this registry's current values through a
/// [GraphEvalContext] (via [snapshot]) so a `var = x` edge actually opens and
/// closes as the performance moves the variable — rather than matching against
/// an empty context, as it did while the picker's name/value were free text.
///
/// Surfaced to the MIDI graph exactly the way [StateGraph] is: owned once
/// (by the engine), passed into the surface and the player, and listened to so
/// a value change repaints the preview and re-routes the sounding notes.
///
/// A [ChangeNotifier] like [StateGraph]: it notifies on every mutation
/// (define / remove / value change), and [version] bumps alongside so painters
/// can compare a cheap int in `shouldRepaint`.
class RuntimeVariableRegistry extends ChangeNotifier {
  final Map<String, RuntimeVariable> _byName = {};
  int _version = 0;

  /// Bumps on every notify — a cheap repaint signal for painters.
  int get version => _version;

  /// The defined variables in definition order. Widgets should treat this as a
  /// set keyed by [RuntimeVariable.name].
  Iterable<RuntimeVariable> get variables => _byName.values;

  /// Whether a variable named [name] is defined.
  bool contains(String name) => _byName.containsKey(name);

  /// The variable named [name], or `null` if undefined.
  RuntimeVariable? byName(String name) => _byName[name];

  /// Define — or redefine — [name] over the candidate [values]. On a redefine
  /// the previous current value is kept if it is still a candidate, otherwise
  /// it resets to the first value (see [RuntimeVariable]'s constructor). Returns
  /// the stored variable and notifies so the picker and any live guard refresh.
  RuntimeVariable define({
    required String name,
    required List<String> values,
    String? current,
  }) {
    final resolvedCurrent = current ?? _byName[name]?.current;
    final variable = RuntimeVariable(
      name: name,
      values: values,
      current: resolvedCurrent,
    );
    _byName[name] = variable;
    _bumpAndNotify();
    return variable;
  }

  /// Remove the variable named [name], if defined, and notify. Any edge still
  /// guarded on it keeps its [RuntimeVariableCondition] — but with the variable
  /// gone the context no longer carries a value for it, so the guard only
  /// matches a `null` expectation (i.e. it closes for any concrete value).
  void remove(String name) {
    if (_byName.remove(name) != null) _bumpAndNotify();
  }

  /// Set the live value of [name] to [value]. No-op — and no notify — when the
  /// variable is unknown, [value] is not one of its candidates, or it is
  /// already current. Returns whether anything changed.
  bool setValue(String name, String value) {
    final variable = _byName[name];
    if (variable == null) return false;
    if (!variable.setCurrent(value)) return false;
    _bumpAndNotify();
    return true;
  }

  /// The current values as the `name → value` map [GraphEvalContext.variables]
  /// consumes. A fresh, detached map each call — safe to hand to a context that
  /// outlives the next mutation.
  Map<String, Object?> snapshot() => {
    for (final v in _byName.values) v.name: v.current,
  };

  void _bumpAndNotify() {
    _version++;
    notifyListeners();
  }
}
