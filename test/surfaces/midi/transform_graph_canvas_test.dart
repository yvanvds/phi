import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/midi_graph/transform_node_frame.dart';
import 'package:phi/domain/midi/graph/graph_eval_context.dart';
import 'package:phi/domain/midi/graph/runtime_variable_condition.dart';
import 'package:phi/domain/midi/graph/state_match_condition.dart';
import 'package:phi/domain/midi/graph/transform_node_id.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/domain/runtime/runtime_variable_registry.dart';
import 'package:phi/engine/state/midi_graph_controller.dart';
import 'package:phi/engine/state/state_machine_controller.dart';
import 'package:phi/surfaces/midi/graph/transform_graph_canvas.dart';
import 'package:phi/surfaces/midi/graph/transform_graph_node_view.dart';

void main() {
  late MidiTransformChain chain;
  late MidiGraphController controller;
  late StateMachineController states;
  late RuntimeVariableRegistry variables;

  setUp(() {
    chain = MidiTransformChain(
      source: MidiClip(
        bars: 1,
        notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
      ),
      transforms: const [
        TransposeTransform(semitones: 5, label: '+5'),
        TransposeTransform(semitones: 2, label: '+2'),
      ],
    );
    controller = MidiGraphController.seededFrom(chain);
    states = StateMachineController()
      ..addState(name: 'break', position: Offset.zero, voice: 1);
    variables = RuntimeVariableRegistry()
      ..define(name: 'mode', values: ['lead', 'pad']);
  });

  tearDown(() {
    controller.dispose();
    chain.dispose();
    states.dispose();
    variables.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 800,
            child: TransformGraphCanvas(
              controller: controller,
              evalContext: GraphEvalContext(
                activeState: states.graph.activeStateAddress,
                variables: variables.snapshot(),
              ),
              stateGraph: states.graph,
              runtimeVariables: variables,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Global position of a node's output port (a hair inside its right edge so
  // the hit lands on the port, not off the node box).
  Offset portOf(WidgetTester tester, TransformNodeId id) {
    final tl = tester.getRect(find.byType(TransformGraphCanvas)).topLeft;
    return tl + graphNodeRect(controller, id).centerRight - const Offset(6, 0);
  }

  Offset centerOf(WidgetTester tester, TransformNodeId id) {
    final tl = tester.getRect(find.byType(TransformGraphCanvas)).topLeft;
    return tl + graphNodeRect(controller, id).center;
  }

  testWidgets('renders the source, one frame per node, and their labels', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('SOURCE'), findsOneWidget);
    expect(find.byType(TransformNodeFrame), findsNWidgets(2));
    expect(find.text('+5'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
  });

  testWidgets('tapping a node toggles its transform active', (tester) async {
    await pump(tester);
    expect(controller.graph.nodes.first.transform.active, isTrue);

    await tester.tap(find.text('+5'));
    await tester.pump();

    expect(controller.graph.nodes.first.transform.active, isFalse);
  });

  testWidgets('drag-to-connect authors a new edge to a fresh node', (
    tester,
  ) async {
    await pump(tester);
    final target = controller.addNodeAt(
      const TransposeTransform(semitones: 12, label: '+12'),
      const Offset(360, 460),
    );
    await tester.pump();

    final before = controller.graph.edges.length;
    final start = portOf(tester, TransformNodeId.source);
    await tester.dragFrom(start, centerOf(tester, target.id) - start);
    await tester.pump();

    expect(controller.graph.edges.length, before + 1);
    expect(
      controller.graph.edges.any(
        (e) => e.fromId == TransformNodeId.source && e.toId == target.id,
      ),
      isTrue,
    );
  });

  testWidgets('a rejected connection surfaces a feedback banner', (
    tester,
  ) async {
    await pump(tester);
    // source → n0 → n1 already exists; re-dragging n0 → n1 is a duplicate.
    final n0 = controller.graph.nodes[0].id;
    final n1 = controller.graph.nodes[1].id;
    final start = portOf(tester, n0);
    await tester.dragFrom(start, centerOf(tester, n1) - start);
    await tester.pump();

    expect(find.textContaining('ALREADY CONNECTED'), findsOneWidget);
  });

  testWidgets('tapping a cable assigns a state-machine condition', (
    tester,
  ) async {
    await pump(tester);
    final n0 = controller.graph.nodes[0].id;
    final tl = tester.getRect(find.byType(TransformGraphCanvas)).topLeft;
    // Midpoint of the source → n0 cable (both nodes share a y, so the cable is
    // horizontal between the source's right edge and n0's left edge).
    final src = graphNodeRect(controller, TransformNodeId.source);
    final dst = graphNodeRect(controller, n0);
    final mid = Offset((src.right + dst.left) / 2, src.center.dy);
    await tester.tapAt(tl + mid);
    await tester.pumpAndSettle();

    await tester.tap(find.text('state · break'));
    await tester.pumpAndSettle();

    final edge = controller.graph.edges.firstWhere(
      (e) => e.fromId == TransformNodeId.source && e.toId == n0,
    );
    // The picker authors the guard on the state's entity address (issue #240).
    expect(
      edge.condition,
      StateMatchCondition(states.graph.states.first.address),
    );
  });

  testWidgets('tapping a cable assigns a runtime-variable condition', (
    tester,
  ) async {
    await pump(tester);
    final n0 = controller.graph.nodes[0].id;
    final tl = tester.getRect(find.byType(TransformGraphCanvas)).topLeft;
    final src = graphNodeRect(controller, TransformNodeId.source);
    final dst = graphNodeRect(controller, n0);
    final mid = Offset((src.right + dst.left) / 2, src.center.dy);
    await tester.tapAt(tl + mid);
    await tester.pumpAndSettle();

    // The picker offers a concrete guard per (variable, value) pair — no free
    // text. Pick `var · mode = pad`.
    await tester.tap(find.text('var · mode = pad'));
    await tester.pumpAndSettle();

    final edge = controller.graph.edges.firstWhere(
      (e) => e.fromId == TransformNodeId.source && e.toId == n0,
    );
    expect(
      edge.condition,
      const RuntimeVariableCondition(name: 'mode', expected: 'pad'),
    );
  });
}
