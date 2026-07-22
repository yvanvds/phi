import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/fader/phi_fader.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/state/state_entity_selection.dart';
import 'package:phi/engine/state/state_machine_controller.dart';
import 'package:phi/shell/right_inspector/right_inspector.dart';

void main() {
  group('RightInspector', () {
    late SessionState session;
    late StateMachineController states;
    late EntityAddress intro;
    late EntityAddress verse;

    setUp(() {
      session = SessionState();
      // A bare controller over its own scratch registry, seeded with the
      // familiar `intro → verse` pair.
      states = StateMachineController();
      intro = states.addState(name: 'intro', position: const Offset(160, 160));
      verse = states.addState(name: 'verse', position: const Offset(400, 160));
      states.connect(intro, verse);
    });

    tearDown(() {
      states.dispose();
      session.dispose();
    });

    StateEntitySelection selectionOf(EntityAddress address) =>
        StateEntitySelection(controller: states, address: address);

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                const Expanded(child: SizedBox()),
                RightInspector(session: session),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('starts collapsed at 28px showing rotated INSPECTOR label', (
      tester,
    ) async {
      await pump(tester);

      final inspector = find.byType(RightInspector);
      expect(tester.getSize(inspector).width, 28);
      expect(find.text('INSPECTOR'), findsOneWidget);
      expect(find.byType(PhiFader), findsNothing);
    });

    testWidgets('tap expands the inspector to 320px and reveals fader', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.text('INSPECTOR'));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(RightInspector)).width, 320);
      expect(find.byType(PhiFader), findsOneWidget);
      expect(find.text('MASTER'), findsOneWidget);
      expect(find.text('NO SELECTION'), findsOneWidget);
    });

    testWidgets('header tap collapses back to 28px', (tester) async {
      await pump(tester);

      await tester.tap(find.text('INSPECTOR'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(RightInspector)).width, 320);

      await tester.tap(find.text('INSPECTOR'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(RightInspector)).width, 28);
    });

    testWidgets(
      'fader reflects session master volume and forwards drags to it',
      (tester) async {
        // Master volume is session-owned manifest state; the fader binds to it.
        session.setMasterVolume(0.6);
        await pump(tester);

        await tester.tap(find.text('INSPECTOR'));
        await tester.pumpAndSettle();

        // Initial readout reflects the session value (0.6).
        expect(find.text('0.60'), findsOneWidget);

        // Drag from the centre of the fader upward → value increases.
        final fader = find.byType(PhiFader);
        final rect = tester.getRect(fader);
        final g = await tester.startGesture(rect.center);
        await g.moveTo(Offset(rect.center.dx, rect.top + 4));
        await g.up();
        await tester.pump();

        expect(session.masterVolume.value, greaterThan(0.6));
      },
    );

    testWidgets(
      'selecting a state entity replaces NO SELECTION with the state panel',
      (tester) async {
        await pump(tester);

        await tester.tap(find.text('INSPECTOR'));
        await tester.pumpAndSettle();

        expect(find.text('NO SELECTION'), findsOneWidget);

        session.select(selectionOf(intro));
        await tester.pump();

        expect(find.text('NO SELECTION'), findsNothing);
        // STATE caption + inline name + entity address + the real panels
        // (issue #245): SLICES / ON ENTER / TRANSITIONS.
        expect(find.text('STATE'), findsOneWidget);
        expect(find.text('intro'), findsOneWidget);
        expect(find.text('state.intro'), findsOneWidget);
        expect(find.text('SLICES'), findsOneWidget);
        expect(find.text('ON ENTER'), findsOneWidget);
        expect(find.text('TRANSITIONS'), findsOneWidget);
        expect(find.text('→ verse'), findsOneWidget);
        expect(find.text('manual'), findsOneWidget);

        session.clearSelection();
        await tester.pump();
        expect(find.text('NO SELECTION'), findsOneWidget);
        expect(find.text('intro'), findsNothing);
      },
    );

    testWidgets('a state without outbound transitions renders the em-dash', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('INSPECTOR'));
      await tester.pumpAndSettle();

      session.select(selectionOf(verse));
      await tester.pump();

      expect(find.text('TRANSITIONS'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets(
      'editing the name renames the entity and re-publishes the selection',
      (tester) async {
        await pump(tester);
        await tester.tap(find.text('INSPECTOR'));
        await tester.pumpAndSettle();

        session.select(selectionOf(verse));
        await tester.pump();

        await tester.tap(find.text('verse'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'chorus');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        // The rename is a registry refactor: the entity moved, intro's
        // transition target followed, and the selection tracks the new
        // address so the panel keeps rendering the same state.
        final chorus = EntityAddress.parse('state.chorus');
        expect(states.nodeAt(chorus), isNotNull);
        expect(states.nodeAt(verse), isNull);
        final selected = session.selection.value;
        expect(selected, isA<StateEntitySelection>());
        expect((selected as StateEntitySelection).address, chorus);
        expect(find.text('chorus'), findsOneWidget);
        expect(find.text('state.chorus'), findsOneWidget);
      },
    );

    testWidgets('a stale selection falls back to NO SELECTION', (tester) async {
      await pump(tester);
      await tester.tap(find.text('INSPECTOR'));
      await tester.pumpAndSettle();

      session.select(selectionOf(verse));
      await tester.pump();
      expect(find.text('STATE'), findsOneWidget);

      // The selected entity is deleted from elsewhere — the panel drops
      // back to the empty state instead of rendering a dangling address.
      states.removeState(verse);
      await tester.pumpAndSettle();

      expect(find.text('NO SELECTION'), findsOneWidget);
    });
  });
}
