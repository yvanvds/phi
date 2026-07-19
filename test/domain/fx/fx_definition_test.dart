import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/fx/fx_definition.dart';
import 'package:phi/domain/fx/fx_kind.dart';

void main() {
  group('FxDefinition', () {
    test('round-trips through JSON', () {
      const fx = FxDefinition(
        kind: FxKind.lowpassDelay,
        params: {'taps': 4.0, 'impact': 0.5, 'feedback': 0.3},
      );
      expect(FxDefinition.fromJson(fx.toJson()), fx);
    });

    test('round-trips a param-free effect', () {
      const fx = FxDefinition(kind: FxKind.phaser);
      expect(FxDefinition.fromJson(fx.toJson()), fx);
    });

    test('toJson tags the kind and sorts params for a stable encoding', () {
      expect(
        const FxDefinition(
          kind: FxKind.granulator,
          params: {'impact': 0.5, 'density': 0.8, 'age': 0.1},
        ).toJson(),
        {
          'kind': 'granulator',
          'params': {'age': 0.1, 'density': 0.8, 'impact': 0.5},
        },
      );
    });

    test('reads integral param values as doubles', () {
      final fx = FxDefinition.fromJson(const {
        'kind': 'basicDelay',
        'params': {'taps': 3},
      });
      expect(fx.params['taps'], 3.0);
    });

    test('withParam sets or adds a single knob', () {
      const fx = FxDefinition(kind: FxKind.compressor, params: {'ratio': 4.0});
      final louder = fx.withParam('threshold', -12.0);
      expect(louder.params, {'ratio': 4.0, 'threshold': -12.0});
      expect(fx.withParam('ratio', 8.0).params['ratio'], 8.0);
    });

    test('a missing kind throws', () {
      expect(
        () => FxDefinition.fromJson(const {'params': <String, Object?>{}}),
        throwsFormatException,
      );
    });

    test('an unknown kind throws', () {
      expect(
        () => FxDefinition.fromJson(const {'kind': 'bitcrusher'}),
        throwsFormatException,
      );
    });

    test('equality is by value and param-order-independent', () {
      expect(
        const FxDefinition(kind: FxKind.sweep, params: {'a': 1.0, 'b': 2.0}),
        const FxDefinition(kind: FxKind.sweep, params: {'b': 2.0, 'a': 1.0}),
      );
      expect(
        const FxDefinition(kind: FxKind.sweep),
        isNot(const FxDefinition(kind: FxKind.phaser)),
      );
    });

    test('every fx kind serialises by name', () {
      for (final kind in FxKind.values) {
        final fx = FxDefinition(kind: kind);
        expect(FxDefinition.fromJson(fx.toJson()).kind, kind);
      }
    });
  });
}
