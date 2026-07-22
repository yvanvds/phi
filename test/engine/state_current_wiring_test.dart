import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/code/code_script.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/state_machine/store/state_document.dart';
import 'package:phi/domain/state_machine/store/state_seed.dart';
import 'package:phi/engine/engine.dart';

import 'test_doubles/fake_code_evaluator.dart';
import 'test_doubles/fake_yse_gateway.dart';

/// Proves the `state.current` mirror (issue #246) is wired into [PhiEngine]
/// end to end: the live state reaches the shared script evaluator as
/// `phi._sync_state_current(...)` pushes — seeded at boot, re-pushed on every
/// entry and rename, ordered ahead of an entry's on-enter script, and
/// re-seeded across a stop → start interpreter re-init.
void main() {
  Iterable<String> pushes(FakeCodeEvaluator evaluator) =>
      evaluator.calls.where((c) => c.startsWith('phi._sync_state_current'));

  late FakeYseGateway gateway;
  late FakeCodeEvaluator evaluator;
  late PhiEngine engine;

  setUp(() {
    gateway = FakeYseGateway();
    evaluator = FakeCodeEvaluator();
    engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await gateway.dispose();
    await evaluator.dispose();
  });

  test('boot seeds state.current for an evaluator wired before start', () {
    engine.stateScriptEvaluator = evaluator;
    engine.start();

    expect(pushes(evaluator), ["phi._sync_state_current('intro')"]);
  });

  test('wiring the evaluator after start seeds immediately', () {
    engine.start();
    expect(evaluator.calls, isEmpty);

    engine.stateScriptEvaluator = evaluator;

    expect(pushes(evaluator), ["phi._sync_state_current('intro')"]);
  });

  test('an entry re-pushes the entered state', () {
    engine.stateScriptEvaluator = evaluator;
    engine.start();

    engine.stateMachine.setLive(verseStateAddress);

    expect(pushes(evaluator).last, "phi._sync_state_current('verse')");
  });

  test('a rename of the live state re-pushes the remapped path', () {
    engine.stateScriptEvaluator = evaluator;
    engine.start();

    engine.stateMachine.rename(introStateAddress, 'opening');

    expect(pushes(evaluator).last, "phi._sync_state_current('opening')");
  });

  test('the push precedes the entered state on-enter script', () {
    // A bound project carrying an on-enter script on `verse` — the entry must
    // queue the current-state sync ahead of the script, so the script already
    // reads the new `state.current`.
    final project = ProjectRegistry();
    addTearDown(project.dispose);
    final script = EntityAddress.parse('code.hello');
    project.createEntity(
      script,
      payload: const CodeScript(source: 'print("entered")').toJson(),
    );
    project.createEntity(introStateAddress, payload: introStateDocument());
    project.createEntity(
      verseStateAddress,
      payload: StateDocument(position: const Offset(400, 160), onEnter: script),
    );
    engine.bindProject(project);
    engine.stateScriptEvaluator = evaluator;
    engine.start();

    engine.stateMachine.setLive(verseStateAddress);

    final calls = evaluator.calls;
    final push = calls.indexOf("phi._sync_state_current('verse')");
    final onEnter = calls.indexOf('print("entered")');
    expect(push, isNot(-1));
    expect(onEnter, isNot(-1));
    expect(push, lessThan(onEnter));
  });

  test('a stop → start re-init re-seeds the fresh interpreter', () {
    engine.stateScriptEvaluator = evaluator;
    engine.start();
    expect(pushes(evaluator), hasLength(1));

    engine.stop();
    engine.start();

    expect(pushes(evaluator), [
      "phi._sync_state_current('intro')",
      "phi._sync_state_current('intro')",
    ]);
  });
}
