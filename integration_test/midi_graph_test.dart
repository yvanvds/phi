import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/midi/graph/state_match_condition.dart';
import 'package:phi/domain/midi/graph/transform_node_id.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/midi/piano_roll_editor.dart';
import 'package:phi/surfaces/midi/transform_chain_panel.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end for the node-and-cable transform-graph editor (issue #65).
///
/// Drives the real [PhiApp] so the whole stack is exercised: the shell sources
/// the graph from `engine.midi.graphController`, the MIDI surface's `GRAPH`
/// toggle swaps in the canvas, and the state machine's `activeStateId` flows
/// through the live `GraphEvalContext` into the preview strip. A branch guarded
/// by a state condition is dark until that state goes live — at which point the
/// preview grows, on-screen, without touching the source clip.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('graph mode: a state-guarded branch changes the live preview', (
    tester,
  ) async {
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // Two performance states; `main` live, `break` dormant.
    final main = engine.stateMachine.addState(
      name: 'main',
      position: const Offset(160, 160),
      voice: 1,
    );
    final brk = engine.stateMachine.addState(
      name: 'break',
      position: const Offset(360, 160),
      voice: 3,
    );
    engine.stateMachine.setActive(main.id);

    // Open the MIDI surface — a chain clip by default: the chip sidebar is up.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    expect(find.byType(TransformChainPanel), findsOneWidget);

    // Switch the clip to graph mode.
    await tester.tap(find.text('GRAPH'));
    await tester.pumpAndSettle();

    // The canvas is up (source node + the seeded chain) and the preview shows
    // the demo phrase's ten notes. The chip sidebar is gone — a graph clip
    // authors its transforms as nodes, so the linear chain editor has no place
    // (issue #77).
    expect(find.text('SOURCE'), findsOneWidget);
    expect(find.textContaining('PREVIEW · 10 NOTES'), findsOneWidget);
    expect(find.byType(TransformChainPanel), findsNothing);

    // Author a branch off the source, guarded by `break`: a new terminal node
    // that only carries notes while break is live. (The drag-to-connect and
    // condition-menu gestures are covered by the canvas widget test; here we
    // author through the same controller the surface is bound to, then verify
    // the *live wiring* — state → context → preview — through the real app.)
    final graph = engine.midi.graphController;
    final branch = graph.addNodeAt(
      const TransposeTransform(semitones: 12, label: 'branch · +12'),
      const Offset(200, 360),
    );
    graph.connect(
      TransformNodeId.source,
      branch.id,
      condition: StateMatchCondition(brk.id),
    );
    await tester.pumpAndSettle();

    // Under `main` the branch edge is closed → preview unchanged.
    expect(find.textContaining('PREVIEW · 10 NOTES'), findsOneWidget);

    // Go live on `break` → the branch opens and its terminal's ten notes join
    // the output. The preview reflects the active subgraph, live.
    engine.stateMachine.setActive(brk.id);
    await tester.pumpAndSettle();
    expect(find.textContaining('PREVIEW · 20 NOTES'), findsOneWidget);

    // Back to `break` off → main → preview returns to ten.
    engine.stateMachine.setActive(main.id);
    await tester.pumpAndSettle();
    expect(find.textContaining('PREVIEW · 10 NOTES'), findsOneWidget);

    // The toggle returns to the linear editor — piano roll and chip sidebar
    // both back.
    await tester.tap(find.text('CHAIN'));
    await tester.pumpAndSettle();
    expect(find.byType(PianoRollEditor), findsOneWidget);
    expect(find.byType(TransformChainPanel), findsOneWidget);

    session.dispose();
    await engine.dispose();
  });
}
