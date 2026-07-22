import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/registry_mirror_factory.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/surfaces/mix/mix_surface.dart';

import '../test/engine/test_doubles/fake_code_evaluator.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that the live name table populates through the real
/// workstation (issue #314): a performer creating and renaming a `mix.` entity
/// on the Mix surface must push the matching `phi._sync_*` scripts through the
/// **same** evaluator the Code surface runs blocks on. The embedded CPython
/// interpreter can't run in CI, so a shared [FakeCodeEvaluator] stands in for the
/// real one — wired exactly the way the app composition root wires it, via
/// [buildRegistryMirror] over that evaluator — and the pushed scripts are the
/// observable that proves the name table would repopulate on a Python build.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a mix create + rename push _sync scripts through the evaluator', (
    tester,
  ) async {
    final gateway = FakeYseGateway();
    // One evaluator backs both the registry mirror and the Code surface — the
    // shared ordered queue the wiring guarantees (issue #314).
    final evaluator = FakeCodeEvaluator();
    final engine = PhiEngine(
      gateway,
      registryMirror: buildRegistryMirror(evaluator, pythonEnabled: true),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(
      PhiApp(engine: engine, session: session, codeEvaluator: evaluator),
    );
    await tester.pumpAndSettle();

    // Mix is the default surface. Add a channel through the '+' menu (design §7).
    await tester.tap(
      find.descendant(of: find.byType(MixSurface), matching: find.text('+')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('add channel'));
    await tester.pumpAndSettle();

    expect(engine.channels.value.map((c) => c.name), ['ch_1']);
    // Creating the entity pushed a `_sync_create` for its address.
    expect(evaluator.calls, contains("phi._sync_create('mix.ch_1')"));

    // Inline-rename it: 'lead synth' slugs to `mix.lead_synth`, an in-place
    // rename (same parent), so the mirror pushes a `_sync_rename`.
    await tester.tap(find.text('ch_1'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'lead synth');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(engine.channels.value.map((c) => c.name), ['lead_synth']);
    expect(
      evaluator.calls,
      contains("phi._sync_rename('mix.ch_1', 'mix.lead_synth')"),
    );

    session.dispose();
    await engine.dispose();
    await evaluator.dispose();
    await gateway.dispose();
  });
}
