import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/fader/phi_fader.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/right_inspector/right_inspector.dart';

import '../../engine/test_doubles/fake_yse_gateway.dart';

void main() {
  group('RightInspector', () {
    late FakeYseGateway gateway;
    late PhiEngine engine;

    setUp(() {
      gateway = FakeYseGateway()..masterVolumeValue = 0.6;
      engine = PhiEngine(
        gateway,
        telemetryInterval: const Duration(milliseconds: 500),
      );
      engine.start();
    });

    tearDown(() async {
      await engine.dispose();
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                const Expanded(child: SizedBox()),
                RightInspector(engine: engine),
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
  });
}
