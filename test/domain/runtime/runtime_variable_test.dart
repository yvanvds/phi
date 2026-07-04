import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/runtime/runtime_variable.dart';

void main() {
  group('RuntimeVariable', () {
    test('defaults current to the first value', () {
      final v = RuntimeVariable(name: 'mode', values: ['lead', 'pad']);
      expect(v.current, 'lead');
    });

    test('honours a current that is one of the values', () {
      final v = RuntimeVariable(
        name: 'mode',
        values: ['lead', 'pad'],
        current: 'pad',
      );
      expect(v.current, 'pad');
    });

    test('falls back to the first value when current is not a candidate', () {
      final v = RuntimeVariable(
        name: 'mode',
        values: ['lead', 'pad'],
        current: 'bass',
      );
      expect(v.current, 'lead');
    });

    test('drops duplicate values, keeping the first occurrence', () {
      final v = RuntimeVariable(name: 'mode', values: ['a', 'b', 'a', 'b']);
      expect(v.values, ['a', 'b']);
    });

    test('exposes an unmodifiable values list', () {
      final v = RuntimeVariable(name: 'mode', values: ['a']);
      expect(() => v.values.add('b'), throwsUnsupportedError);
    });

    test('setCurrent moves to a candidate and reports the change', () {
      final v = RuntimeVariable(name: 'mode', values: ['lead', 'pad']);
      expect(v.setCurrent('pad'), isTrue);
      expect(v.current, 'pad');
    });

    test('setCurrent rejects a non-candidate and leaves current untouched', () {
      final v = RuntimeVariable(name: 'mode', values: ['lead', 'pad']);
      expect(v.setCurrent('bass'), isFalse);
      expect(v.current, 'lead');
    });

    test('setCurrent to the already-current value is a no-op', () {
      final v = RuntimeVariable(name: 'mode', values: ['lead', 'pad']);
      expect(v.setCurrent('lead'), isFalse);
    });
  });
}
