import '../../domain/runtime/runtime_variable_registry.dart';
import '../bridge/variable_control_port.dart';

/// The live [RuntimeVariableRegistry] as the control plane's [VariableControlPort]
/// — the receiving end of `phi.ctl.var.*` assignments (design
/// `docs/design/live-coding.md` §4, issue #233; production wiring #334).
///
/// A script `var.section = "b"` publishes `phi.ctl.var.section` carrying the
/// value; the [ControlPlaneDispatcher] decodes it and calls [set]. Runtime
/// variable values settle as **strings** (enumerated choices, issue #78), so a
/// non-string bus value is coerced to its string form before the store's own
/// candidate check. Everything degrades **gracefully**: a `null` value, an
/// unknown variable name, or a value that is not one of the variable's
/// candidates is a silent no-op ([RuntimeVariableRegistry.setValue] returns
/// `false`) — never a throw, so a stray assignment from live code cannot tear
/// down the tap.
class RuntimeVariableControlPort implements VariableControlPort {
  const RuntimeVariableControlPort(this._variables);

  final RuntimeVariableRegistry _variables;

  @override
  void set(String name, Object? value) {
    if (value == null) return;
    _variables.setValue(name, value is String ? value : value.toString());
  }
}
