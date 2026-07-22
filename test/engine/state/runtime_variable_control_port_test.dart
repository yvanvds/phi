import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/runtime/runtime_variable_registry.dart';
import 'package:phi/engine/state/runtime_variable_control_port.dart';

/// The real `var` leg of the control plane (issue #334): a decoded
/// `phi.ctl.var.*` assignment drives [RuntimeVariableRegistry.setValue],
/// degrading gracefully for unknown names / non-candidate values.
void main() {
  late RuntimeVariableRegistry registry;
  late RuntimeVariableControlPort port;

  setUp(() {
    registry = RuntimeVariableRegistry()
      ..define(name: 'section', values: ['a', 'b'], current: 'a')
      ..define(name: 'count', values: ['1', '2', '3'], current: '1');
    port = RuntimeVariableControlPort(registry);
  });

  tearDown(() => registry.dispose());

  test('a string assignment sets a candidate value', () {
    port.set('section', 'b');
    expect(registry.byName('section')!.current, 'b');
  });

  test('a non-string value is coerced to its string form', () {
    // `var.count = 3` rides the bus as an int; the store holds string choices.
    port.set('count', 3);
    expect(registry.byName('count')!.current, '3');
  });

  test('an unknown variable name is a silent no-op', () {
    port.set('unknown', 'x');
    expect(registry.contains('unknown'), isFalse);
    // The known variables are untouched.
    expect(registry.byName('section')!.current, 'a');
  });

  test('a value that is not one of the candidates is a silent no-op', () {
    port.set('section', 'z'); // not in [a, b]
    expect(registry.byName('section')!.current, 'a');
  });

  test('a null value is a no-op', () {
    port.set('section', null);
    expect(registry.byName('section')!.current, 'a');
  });
}
