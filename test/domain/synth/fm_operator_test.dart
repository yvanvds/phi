import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/synth/fm_operator.dart';

void main() {
  group('FmOperator', () {
    test('round-trips through JSON', () {
      const op = FmOperator(
        op: 3,
        enabled: false,
        outputLevel: 80,
        freqCoarse: 14,
        freqFine: 22,
        detune: 3,
      );
      expect(FmOperator.fromJson(op.toJson()), op);
    });

    test('toJson emits the op index and every field in a stable order', () {
      expect(const FmOperator(op: 0).toJson(), {
        'op': 0,
        'enabled': true,
        'outputLevel': 99,
        'freqCoarse': 1,
        'freqFine': 0,
        'detune': 7,
      });
    });

    test('fromJson requires an op index', () {
      expect(
        () => FmOperator.fromJson(const {'outputLevel': 50}),
        throwsFormatException,
      );
    });

    test('fromJson fills defaults for the other fields', () {
      final op = FmOperator.fromJson(const {'op': 5});
      expect(op, const FmOperator(op: 5));
    });

    test('equality and hashCode are by value', () {
      expect(const FmOperator(op: 1), const FmOperator(op: 1));
      expect(
        const FmOperator(op: 1).hashCode,
        const FmOperator(op: 1).hashCode,
      );
      expect(const FmOperator(op: 1), isNot(const FmOperator(op: 2)));
    });
  });
}
