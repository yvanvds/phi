import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/fx/fx_definition.dart';
import 'package:phi/domain/fx/fx_kind.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/registry_kinds.dart';

void main() {
  EntityAddress patch(String name) =>
      EntityAddress(kind: RegistryKinds.patch, segments: [name]);

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

    group('patcher-insert reference (issue #225)', () {
      test('a patcher insert carries and round-trips its wrapped patch', () {
        final fx = FxDefinition(
          kind: FxKind.patcherInsert,
          patch: patch('swirl'),
        );
        expect(fx.toJson()['patch'], 'patch.swirl');
        expect(FxDefinition.fromJson(fx.toJson()), fx);
        expect(FxDefinition.fromJson(fx.toJson()).patch, patch('swirl'));
      });

      test('references the wrapped patch — nothing for any other kind', () {
        expect(
          FxDefinition(
            kind: FxKind.patcherInsert,
            patch: patch('swirl'),
          ).references,
          {patch('swirl')},
        );
        expect(const FxDefinition(kind: FxKind.lowpass).references, isEmpty);
        // A patcher insert without a patch (malformed) references nothing.
        expect(
          const FxDefinition(kind: FxKind.patcherInsert).references,
          isEmpty,
        );
      });

      test('withReferenceUpdated repoints the wrapped patch', () {
        final fx = FxDefinition(
          kind: FxKind.patcherInsert,
          patch: patch('swirl'),
        );
        final moved = fx.withReferenceUpdated(patch('swirl'), patch('swirl_2'));
        expect(moved.patch, patch('swirl_2'));
        // The inverse restores the original (undo round-trips).
        expect(
          moved.withReferenceUpdated(patch('swirl_2'), patch('swirl')).patch,
          patch('swirl'),
        );
        // A reference it does not hold is left untouched.
        expect(
          fx.withReferenceUpdated(patch('other'), patch('x')).patch,
          patch('swirl'),
        );
      });

      test('equality is by value including the wrapped patch', () {
        expect(
          FxDefinition(kind: FxKind.patcherInsert, patch: patch('a')),
          FxDefinition(kind: FxKind.patcherInsert, patch: patch('a')),
        );
        expect(
          FxDefinition(kind: FxKind.patcherInsert, patch: patch('a')),
          isNot(FxDefinition(kind: FxKind.patcherInsert, patch: patch('b'))),
        );
      });

      test('a plain effect emits no patch key', () {
        expect(
          const FxDefinition(
            kind: FxKind.lowpass,
          ).toJson().containsKey('patch'),
          isFalse,
        );
      });
    });
  });
}
