import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/dialog/delete_impact_dialog.dart';
import 'package:phi/design/widgets/state_machine/state_node_frame.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/state/state_entity_selection.dart';
import 'package:phi/engine/state/state_machine_controller.dart';
import 'package:phi/surfaces/state/state_canvas.dart';

/// The registry-backed canvas affordances (issue #241): context menus for
/// new / duplicate / delete, the delete-impact guardrail, and selection
/// publishing the `state.` entity.
void main() {
  late StateMachineController controller;
  late SessionState session;
  late EntityAddress intro;
  late EntityAddress verse;

  setUp(() {
    controller = StateMachineController();
    session = SessionState();
    intro = controller.addState(
      name: 'intro',
      position: const Offset(160, 160),
    );
    verse = controller.addState(
      name: 'verse',
      position: const Offset(400, 160),
    );
    controller.connect(intro, verse);
  });

  tearDown(() {
    controller.dispose();
    session.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StateCanvas(controller: controller, session: session),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> rightClickAt(WidgetTester tester, Offset canvasLocal) async {
    final origin = tester.getTopLeft(find.byType(StateCanvas));
    await tester.tapAt(origin + canvasLocal, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
  }

  Future<void> rightClickNode(WidgetTester tester, String name) async {
    await tester.tap(find.text(name), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
  }

  group('canvas context menu', () {
    testWidgets('new state creates a node at the click and selects it', (
      tester,
    ) async {
      await pump(tester);

      // Empty spot, grid-aligned so the snapped position equals the click.
      await rightClickAt(tester, const Offset(608, 400));
      expect(find.text('new state'), findsOneWidget);
      await tester.tap(find.text('new state'));
      await tester.pumpAndSettle();

      expect(controller.states, hasLength(3));
      final added = EntityAddress.parse('state.state');
      expect(controller.nodeAt(added)?.position, const Offset(608, 400));
      final selected = session.selection.value;
      expect(selected, isA<StateEntitySelection>());
      expect((selected as StateEntitySelection).address, added);
      expect(find.byType(StateNodeFrame), findsNWidgets(3));
    });
  });

  group('node context menu', () {
    testWidgets('duplicate copies the node beside the original and selects '
        'the copy', (tester) async {
      await pump(tester);

      await rightClickNode(tester, 'verse');
      expect(find.text('duplicate'), findsOneWidget);
      expect(find.text('delete'), findsOneWidget);
      await tester.tap(find.text('duplicate'));
      await tester.pumpAndSettle();

      final copy = EntityAddress.parse('state.verse_copy');
      expect(controller.nodeAt(copy), isNotNull);
      expect(controller.nodeAt(copy)!.position, const Offset(432, 192));
      final selected = session.selection.value;
      expect((selected as StateEntitySelection).address, copy);
    });

    testWidgets('delete on a referenced state raises the impact dialog; '
        'cancel keeps it', (tester) async {
      await pump(tester);

      await rightClickNode(tester, 'verse');
      await tester.tap(find.text('delete'));
      await tester.pumpAndSettle();

      // `intro` still points at `verse` — the guardrail lists it.
      expect(find.byType(DeleteImpactDialog), findsOneWidget);
      expect(find.text('delete verse?'), findsOneWidget);
      expect(find.text('• state.intro'), findsOneWidget);

      await tester.tap(find.text('cancel'));
      await tester.pumpAndSettle();
      expect(controller.nodeAt(verse), isNotNull);
      expect(find.byType(StateNodeFrame), findsNWidgets(2));
    });

    testWidgets('confirming the impact dialog removes the state and clears '
        'its inbound transition', (tester) async {
      await pump(tester);
      session.select(
        StateEntitySelection(controller: controller, address: verse),
      );

      await rightClickNode(tester, 'verse');
      await tester.tap(find.text('delete'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DeleteImpactDialog),
          matching: find.text('delete'),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.nodeAt(verse), isNull);
      expect(controller.transitions, isEmpty);
      expect(find.byType(StateNodeFrame), findsOneWidget);
      // The deleted entity's selection was cleared, not left dangling.
      expect(session.selection.value, isNull);
    });

    testWidgets('delete on an unreferenced state skips the dialog', (
      tester,
    ) async {
      await pump(tester);

      // Nothing points at `intro` (its transition is outbound).
      await rightClickNode(tester, 'intro');
      await tester.tap(find.text('delete'));
      await tester.pumpAndSettle();

      expect(find.byType(DeleteImpactDialog), findsNothing);
      expect(controller.nodeAt(intro), isNull);
      expect(find.byType(StateNodeFrame), findsOneWidget);
    });
  });
}
