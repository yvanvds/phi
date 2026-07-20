import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/fx/fx_definition.dart';
import 'package:phi/domain/fx/fx_kind.dart';

import '../test_doubles/fake_fx_gateway.dart';

/// The fake fx gateway models the whole surface the session layer (#208) drives:
/// per-kind materialisation, click-free vs. rebuild re-application, and
/// cycle-safe chain build / reorder / detach (design
/// `docs/design/racks-and-voices.md` §5).
void main() {
  late FakeFxGateway gateway;

  setUp(() => gateway = FakeFxGateway());

  FakeMaterialisedFx materialise(
    FxKind kind, [
    Map<String, double> params = const {},
  ]) =>
      gateway.materialiseFx(FxDefinition(kind: kind, params: params))
          as FakeMaterialisedFx;

  group('materialisation', () {
    test('every fx kind materialises a handle', () {
      for (final kind in FxKind.values) {
        final fx = materialise(kind);
        expect(fx.kind, kind);
        expect(fx.materialiseCount, 1);
        expect(fx.calls.first, 'materialise:${kind.name}');
      }
      expect(gateway.handles, hasLength(FxKind.values.length));
    });

    test('every kind but the reserved patcherInsert is placeable', () {
      for (final kind in FxKind.values) {
        expect(
          materialise(kind).isPlaceable,
          kind != FxKind.patcherInsert,
          reason: '$kind placeable',
        );
      }
    });
  });

  group('re-application', () {
    test('a same-kind param edit applies live (click-free)', () {
      final fx = materialise(FxKind.lowpassDelay, {'impact': 0.3});
      fx.applyDefinition(
        const FxDefinition(kind: FxKind.lowpassDelay, params: {'impact': 0.6}),
      );
      expect(fx.materialiseCount, 1); // no rebuild
      expect(fx.liveApplyCount, 1);
      expect(fx.definition.params['impact'], 0.6);
      expect(fx.calls, ['materialise:lowpassDelay', 'apply:lowpassDelay']);
    });

    test('a kind change rebuilds the underlying effect', () {
      final fx = materialise(FxKind.lowpass);
      fx.applyDefinition(const FxDefinition(kind: FxKind.phaser));
      expect(fx.materialiseCount, 2);
      expect(fx.liveApplyCount, 0);
      expect(fx.kind, FxKind.phaser);
      expect(fx.calls, ['materialise:lowpass', 'materialise:phaser']);
    });
  });

  group('chain build / reorder / detach', () {
    test('build links inserts in order and attaches the head', () {
      final chain = gateway.createChain(busChannelId: 7) as FakeFxChain;
      final a = materialise(FxKind.lowpass);
      final b = materialise(FxKind.basicDelay);
      final c = materialise(FxKind.compressor);

      chain.setInserts([a, b, c]);

      expect(chain.busChannelId, 7);
      expect(chain.attached, isTrue);
      expect(chain.inserts, [a, b, c]);
      // The engine-visible walk (head → … → terminator) matches the order.
      expect(chain.walkFromHead(), [a, b, c]);
    });

    test('reorder re-links without closing a cycle', () {
      final chain = gateway.createChain(busChannelId: 1) as FakeFxChain;
      final a = materialise(FxKind.lowpass);
      final b = materialise(FxKind.phaser);
      final c = materialise(FxKind.granulator);
      chain.setInserts([a, b, c]);

      // Every permutation must leave an acyclic, correctly-ordered walk — this
      // is exactly the stale-`next` cycle the real terminator prevents.
      for (final order in <List<FakeMaterialisedFx>>[
        [c, a, b],
        [b, c, a],
        [c, b, a],
        [a, c, b],
      ]) {
        chain.setInserts(order);
        expect(chain.walkFromHead(), order, reason: 'walk after reorder');
        expect(chain.attached, isTrue);
      }
    });

    test('removing an insert drops it from the live walk', () {
      final chain = gateway.createChain(busChannelId: 1) as FakeFxChain;
      final a = materialise(FxKind.lowpass);
      final b = materialise(FxKind.phaser);
      final c = materialise(FxKind.compressor);
      chain.setInserts([a, b, c]);

      chain.setInserts([a, c]); // drop b (the middle)
      expect(chain.walkFromHead(), [a, c]);

      chain.setInserts([b]); // drop to just b
      expect(chain.walkFromHead(), [b]);
    });

    test('an empty list detaches the chain from the bus', () {
      final chain = gateway.createChain(busChannelId: 2) as FakeFxChain;
      final a = materialise(FxKind.lowpass);
      chain.setInserts([a]);
      expect(chain.attached, isTrue);

      chain.setInserts([]);
      expect(chain.attached, isFalse);
      expect(chain.inserts, isEmpty);
      expect(chain.walkFromHead(), isEmpty);
    });

    test('a reserved patcherInsert handle is skipped, not placed', () {
      final chain = gateway.createChain(busChannelId: 3) as FakeFxChain;
      final a = materialise(FxKind.lowpass);
      final reserved = materialise(FxKind.patcherInsert);
      final c = materialise(FxKind.compressor);

      chain.setInserts([a, reserved, c]);
      expect(chain.inserts, [a, c]);
      expect(chain.walkFromHead(), [a, c]);
    });
  });

  group('disposal', () {
    test('disposing the chain detaches but does not dispose its handles', () {
      final chain = gateway.createChain(busChannelId: 4) as FakeFxChain;
      final a = materialise(FxKind.lowpass);
      final b = materialise(FxKind.compressor);
      chain.setInserts([a, b]);

      chain.dispose();
      expect(chain.isDisposed, isTrue);
      expect(chain.attached, isFalse);
      // Handles are borrowed — the owner disposes them, not the chain.
      expect(a.isDisposed, isFalse);
      expect(b.isDisposed, isFalse);
    });

    test('disposing a handle is idempotent and logs once', () {
      final fx = materialise(FxKind.lowpass);
      fx.dispose();
      fx.dispose();
      expect(fx.isDisposed, isTrue);
      expect(fx.calls.where((c) => c == 'dispose'), hasLength(1));
    });
  });
}
