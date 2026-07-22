import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/runtime/runtime_variable_registry.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/domain/state_machine/store/state_trigger.dart';
import 'package:phi/domain/time_domains/time_domain.dart';
import 'package:phi/engine/state/state_machine_controller.dart';
import 'package:phi/surfaces/state/state_canvas.dart';
import 'package:phi/surfaces/state/state_transition_badge.dart';
import 'package:phi/surfaces/state/state_trigger_editor.dart';

/// The canvas half of issue #244: every transition badges its trigger kind at
/// the curve midpoint, the badge is the arm toggle for manual transitions
/// (tap-to-arm moved to the badge, design §5) and the editor opener for the
/// rest, and tapping the curve opens the trigger editor for any kind.
void main() {
  late StateMachineController controller;
  late SessionState session;
  late RuntimeVariableRegistry variables;
  late EntityAddress intro;
  late EntityAddress verse;

  final drum = EntityAddress.parse('domain.drum');

  setUp(() {
    controller = StateMachineController();
    session = SessionState();
    variables = RuntimeVariableRegistry()
      ..define(name: 'section', values: ['a', 'b'], current: 'a');
    intro = controller.addState(
      name: 'intro',
      position: const Offset(160, 160),
    );
    verse = controller.addState(
      name: 'verse',
      position: const Offset(400, 160),
    );
    controller.connect(intro, verse);
    controller.registry.createEntity(
      EntityAddress(kind: RegistryKinds.domain, segments: const ['drum']),
      payload: const TimeDomain(name: 'drum', tempo: 124),
    );
  });

  tearDown(() {
    controller.dispose();
    session.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StateCanvas(
            controller: controller,
            session: session,
            variables: variables,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// A canvas-local tap — the canvas sits at the widget's top-left while the
  /// pan/zoom transform is identity.
  Future<void> tapCanvasAt(WidgetTester tester, Offset canvasLocal) async {
    final origin = tester.getTopLeft(find.byType(StateCanvas));
    await tester.tapAt(origin + canvasLocal);
    await tester.pumpAndSettle();
  }

  testWidgets('each transition badges its trigger kind at the curve midpoint', (
    tester,
  ) async {
    await pump(tester);

    final badge = tester.widget<StateTransitionBadge>(
      find.byType(StateTransitionBadge),
    );
    expect(badge.kind, 'manual');
    expect(find.text('MANUAL'), findsOneWidget);

    // The curve between intro (160,160) and verse (400,160) runs along
    // y = 188 from x 280 to x 400 — the badge centre sits at its midpoint.
    final origin = tester.getTopLeft(find.byType(StateCanvas));
    final centre = tester.getCenter(find.byType(StateTransitionBadge));
    expect(centre - origin, const Offset(340, 188));
  });

  testWidgets('the badge kind follows the stored trigger', (tester) async {
    controller.setTrigger(intro, verse, TimedTrigger(beats: 4, domain: drum));
    await pump(tester);
    expect(find.text('TIMED'), findsOneWidget);
  });

  testWidgets('tapping the badge on a manual transition toggles the arm', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.byType(StateTransitionBadge));
    await tester.pump();
    expect(controller.transitions.single.armed, isTrue);
    expect(find.text('▲ ARMED · MANUAL'), findsOneWidget);
    expect(find.byType(StateTriggerEditor), findsNothing);

    await tester.tap(find.byType(StateTransitionBadge));
    await tester.pump();
    expect(controller.transitions.single.armed, isFalse);
  });

  testWidgets('tapping the badge on a non-manual transition opens the editor', (
    tester,
  ) async {
    controller.setTrigger(intro, verse, const CodeTrigger());
    await pump(tester);

    await tester.tap(find.byType(StateTransitionBadge));
    await tester.pumpAndSettle();
    expect(find.byType(StateTriggerEditor), findsOneWidget);
    expect(controller.transitions.single.armed, isFalse);
  });

  testWidgets('tapping the curve opens the trigger editor', (tester) async {
    await pump(tester);

    // On the curve (y = 188) but clear of the badge around x = 340.
    await tapCanvasAt(tester, const Offset(292, 188));
    expect(find.byType(StateTriggerEditor), findsOneWidget);
  });

  testWidgets('saving from the editor writes the trigger through the '
      'controller — kind, beats and domain from the dialog', (tester) async {
    await pump(tester);

    await tapCanvasAt(tester, const Offset(292, 188));
    await tester.tap(find.byKey(StateTriggerEditor.kindKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('timed').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(StateTriggerEditor.beatsKey), '16');
    await tester.tap(find.byKey(StateTriggerEditor.saveKey));
    await tester.pumpAndSettle();

    expect(
      controller.triggerOf(intro, verse),
      TimedTrigger(beats: 16, domain: drum),
    );
    expect(find.text('TIMED'), findsOneWidget);
  });

  testWidgets('the editor offers the wired runtime variables', (tester) async {
    await pump(tester);

    await tapCanvasAt(tester, const Offset(292, 188));
    await tester.tap(find.byKey(StateTriggerEditor.kindKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('variable').last);
    await tester.pumpAndSettle();

    // Defaults to the first defined variable and its first candidate.
    await tester.tap(find.byKey(StateTriggerEditor.valueKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('b').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(StateTriggerEditor.saveKey));
    await tester.pumpAndSettle();

    expect(
      controller.triggerOf(intro, verse),
      const VariableTrigger(name: 'section', value: 'b'),
    );
    expect(find.text('VARIABLE'), findsOneWidget);
  });

  testWidgets('cancelling the editor leaves the trigger untouched', (
    tester,
  ) async {
    await pump(tester);

    await tapCanvasAt(tester, const Offset(292, 188));
    await tester.tap(find.byKey(StateTriggerEditor.cancelKey));
    await tester.pumpAndSettle();
    expect(controller.triggerOf(intro, verse), const ManualTrigger());
    expect(find.text('MANUAL'), findsOneWidget);
  });
}
