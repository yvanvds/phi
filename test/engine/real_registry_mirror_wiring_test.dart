import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/real_registry_mirror.dart';
import 'package:phi/engine/engine.dart';

import 'test_doubles/fake_code_evaluator.dart';
import 'test_doubles/fake_yse_gateway.dart';

/// End-to-end through the seam the live-coding epic hangs the mirror on (issue
/// #231): an engine wired with the *real* [RealRegistryMirror] over a fake
/// evaluator turns channel edits and lifecycle boots into the exact
/// `phi._sync_*(...)` scripts the `phi` library (issue #230) consumes.
void main() {
  late FakeYseGateway gateway;
  late FakeCodeEvaluator evaluator;
  late PhiEngine engine;

  setUp(() {
    gateway = FakeYseGateway();
    evaluator = FakeCodeEvaluator();
    engine = PhiEngine(
      gateway,
      registryMirror: RealRegistryMirror(evaluator),
      telemetryInterval: const Duration(milliseconds: 20),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await evaluator.dispose();
    await gateway.dispose();
  });

  // A bare engine's scratch registry carries the seeded `intro → verse`
  // state pair (issue #241), so every full sync mirrors those entities too.
  test('boot pushes a full-sync script through the evaluator', () async {
    engine.start();
    await pumpEventQueue();

    expect(evaluator.calls, [
      "phi._sync_replace(['state.intro', 'state.verse'])",
    ]);
  });

  test(
    'a channel create pushes _sync_create; boot script precedes it',
    () async {
      engine.start();
      engine.addChannel(name: 'drums');
      await pumpEventQueue();

      expect(evaluator.calls, [
        "phi._sync_replace(['state.intro', 'state.verse'])",
        "phi._sync_create('mix.drums')",
      ]);
    },
  );

  test('a re-init re-pushes the whole tree as one _sync_replace', () async {
    engine.start();
    engine.addChannel(name: 'drums');
    await pumpEventQueue();

    engine.stop();
    engine.start();
    await pumpEventQueue();

    // The final push is the re-init full sync, carrying the surviving channel.
    expect(
      evaluator.calls.last,
      "phi._sync_replace(['state.intro', 'state.verse', 'mix.drums'])",
    );
  });
}
