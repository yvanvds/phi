import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/no_op_registry_mirror.dart';
import 'package:phi/engine/bridge/real_registry_mirror.dart';
import 'package:phi/engine/bridge/registry_mirror_factory.dart';
import 'package:phi/engine/engine.dart';

import '../test_doubles/fake_code_evaluator.dart';
import '../test_doubles/fake_yse_gateway.dart';

/// The factory gates the live name-table mirror behind `LiveCoding.enabled`
/// (issue #314), mirroring `buildCodeEvaluator`: a Python build gets a
/// [RealRegistryMirror] bound to the shared evaluator, a Python-less build the
/// silent [NoOpRegistryMirror]. Both branches are FFI-free — the real mirror
/// only stores the evaluator — so both are asserted headlessly, and the
/// production wiring shape (`PhiEngine` + a factory-built mirror) is exercised
/// end to end over a fake evaluator.
void main() {
  test('returns a NoOpRegistryMirror when Python is disabled', () {
    final evaluator = FakeCodeEvaluator();
    addTearDown(evaluator.dispose);

    final mirror = buildRegistryMirror(evaluator, pythonEnabled: false);
    expect(mirror, isA<NoOpRegistryMirror>());
  });

  test('returns a RealRegistryMirror bound to the evaluator when enabled', () {
    final evaluator = FakeCodeEvaluator();
    addTearDown(evaluator.dispose);

    final mirror = buildRegistryMirror(evaluator, pythonEnabled: true);
    expect(mirror, isA<RealRegistryMirror>());
  });

  test(
    'the production wiring pushes _sync_* scripts through the shared evaluator',
    () async {
      // The exact shape the app composition root builds (issue #314): the engine
      // wired with a factory-built mirror over the *same* evaluator the Code
      // surface runs blocks on. A registry edit must surface as the matching
      // `phi._sync_*` script on that evaluator.
      final gateway = FakeYseGateway();
      final evaluator = FakeCodeEvaluator();
      final engine = PhiEngine(
        gateway,
        registryMirror: buildRegistryMirror(evaluator, pythonEnabled: true),
        telemetryInterval: const Duration(milliseconds: 20),
      );
      addTearDown(() async {
        await engine.dispose();
        await evaluator.dispose();
        await gateway.dispose();
      });

      engine.start();
      engine.addChannel(name: 'drums');
      await pumpEventQueue();

      // The boot full sync of the seeded `intro → verse` states, then the create.
      expect(
        evaluator.calls,
        containsAllInOrder([
          "phi._sync_replace(['state.intro', 'state.verse'])",
          "phi._sync_create('mix.drums')",
        ]),
      );
    },
  );
}
