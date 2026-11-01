import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/dial_mapping.dart';

/// [DialMapping] restates libYSE's `MapRange` for a `.dial`'s readout
/// (issue #470); these pin it to the engine's own cases.
void main() {
  test('no arguments is the 0-1 linear float the engine defaults to', () {
    final m = DialMapping.fromArgs('');
    expect(m.map(0), 0);
    expect(m.map(0.25), 0.25);
    expect(m.map(1), 1);
    expect(m.format(0.5), '0.5');
  });

  test('a range maps linearly and clamps the position first', () {
    final m = DialMapping.fromArgs('20 20000');
    expect(m.map(0), 20);
    expect(m.map(1), 20000);
    expect(m.map(0.5), 10010);
    expect(m.map(2), 20000);
    expect(m.map(-1), 20);
  });

  test('an exponent bends the curve', () {
    final m = DialMapping.fromArgs('0 100 2');
    expect(m.map(0.5), closeTo(25, 1e-9));
  });

  test('int mode rounds half away from zero', () {
    final m = DialMapping.fromArgs('0 127 1 1');
    expect(m.map(0.5), 64);
    expect(m.format(0.5), '64');
    final negative = DialMapping.fromArgs('-127 0 1 1');
    expect(negative.map(0.5), -64);
  });

  test('a reversed range still clamps inside it', () {
    final m = DialMapping.fromArgs('10 0');
    expect(m.map(0), 10);
    expect(m.map(1), 0);
    expect(m.map(0.25), 7.5);
  });

  test('the float readout keeps three decimals at most', () {
    final m = DialMapping.fromArgs('0 1');
    expect(m.format(1 / 3), '0.333');
    expect(m.format(1), '1');
    expect(m.format(0), '0');
  });

  test('unparseable arguments keep their defaults', () {
    final m = DialMapping.fromArgs('low 50 x');
    expect(m.minimum, 0);
    expect(m.maximum, 50);
    expect(m.exponent, 1);
    expect(m.intMode, isFalse);
  });
}
