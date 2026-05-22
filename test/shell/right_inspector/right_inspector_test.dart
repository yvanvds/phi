import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/fader/phi_fader.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/domain/state_machine/performance_state.dart';
import 'package:phi/domain/state_machine/performance_state_id.dart';
import 'package:phi/domain/state_machine/state_snapshot.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/right_inspector/right_inspector.dart';

import '../../engine/test_doubles/fake_yse_gateway.dart';

void main() {
  group('RightInspector', () {
    late FakeYseGateway gateway;
    late PhiEngine engine;
    late SessionState session;

    setUp(() {
      gateway = FakeYseGateway()..masterVolumeValue = 0.6;
      engine = PhiEngine(
        gateway,
        telemetryInterval: const Duration(milliseconds: 500),
      );
      engine.start();
      session = SessionState();
    });

    tearDown(() async {
      session.dispose();
      await engine.dispose();
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                const Expanded(child: SizedBox()),
                RightInspector(engine: engine, session: session),
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

    testWidgets('fader reflects masterVolume and dragging forwards to engine', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.text('INSPECTOR'));
      await tester.pumpAndSettle();

      // Initial readout reflects the seeded gateway value (0.6).
      expect(find.text('0.60'), findsOneWidget);

      // Drag from the centre of the fader upward → value increases.
      final fader = find.byType(PhiFader);
      final rect = tester.getRect(fader);
      final g = await tester.startGesture(rect.center);
      await g.moveTo(Offset(rect.center.dx, rect.top + 4));
      await g.up();
      await tester.pump();

      expect(engine.masterVolume.value, greaterThan(0.6));
      expect(gateway.masterVolumeValue, greaterThan(0.6));
    });

    testWidgets(
      'selecting a PerformanceState replaces NO SELECTION with the state panel',
      (tester) async {
        await pump(tester);

        await tester.tap(find.text('INSPECTOR'));
        await tester.pumpAndSettle();

        expect(find.text('NO SELECTION'), findsOneWidget);

        final state = PerformanceState(
          id: const PerformanceStateId('s1'),
          name: 'intro',
          voice: 1,
          position: Offset.zero,
        );
        session.select(state);
        await tester.pump();

        expect(find.text('NO SELECTION'), findsNothing);
        // STATE caption + DOMAINS / CODE BLOCKS / SCENE REF labels.
        expect(find.text('STATE'), findsOneWidget);
        expect(find.text('intro'), findsOneWidget);
        expect(find.text('DOMAINS'), findsOneWidget);
        expect(find.text('CODE BLOCKS'), findsOneWidget);
        expect(find.text('SCENE REF'), findsOneWidget);
        // All three snapshot sections are empty → three em-dashes.
        expect(find.text('—'), findsNWidgets(3));

        session.clearSelection();
        await tester.pump();
        expect(find.text('NO SELECTION'), findsOneWidget);
        expect(find.text('intro'), findsNothing);
      },
    );

    testWidgets('non-empty snapshot lists render their values', (tester) async {
      await pump(tester);
      await tester.tap(find.text('INSPECTOR'));
      await tester.pumpAndSettle();

      final state = PerformanceState(
        id: const PerformanceStateId('s1'),
        name: 'verse',
        voice: 2,
        position: Offset.zero,
        snapshot: const StateSnapshot(
          domainIds: ['bar.32', 'free'],
          codeBlockIds: ['drone'],
          sceneRef: 'pose-a',
        ),
      );
      session.select(state);
      await tester.pump();

      expect(find.text('bar.32'), findsOneWidget);
      expect(find.text('free'), findsOneWidget);
      expect(find.text('drone'), findsOneWidget);
      expect(find.text('pose-a'), findsOneWidget);
      // No em-dashes when every snapshot section has values.
      expect(find.text('—'), findsNothing);
    });

    testWidgets('editing the name in the inspector renames the state', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('INSPECTOR'));
      await tester.pumpAndSettle();

      final state = PerformanceState(
        id: const PerformanceStateId('s1'),
        name: 'intro',
        voice: 1,
        position: Offset.zero,
      );
      session.select(state);
      await tester.pump();

      await tester.tap(find.text('intro'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'verse');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(state.name, 'verse');
      expect(find.text('verse'), findsOneWidget);
    });
  });
}
