import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/midi/transform_chip.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end add-transform gesture through the real workstation (issue #39):
/// the chain header `+` opens the built-in catalogue menu, picking an entry
/// appends a chip, and the per-chip right-click menu removes it — all against
/// the real shell, real navigation, and the engine's own shared chain.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets(
    'midi: + menu adds a built-in transform, context menu removes it',
    (tester) async {
      final engine = PhiEngine(
        FakeYseGateway(),
        midiGateway: FakeMidiGateway(),
        telemetryInterval: const Duration(milliseconds: 20),
      );
      final session = SessionState();

      await tester.pumpWidget(PhiApp(engine: engine, session: session));
      await tester.pumpAndSettle();

      // Navigate to the MIDI surface (the engine owns the shared chain).
      await tester.tap(railFor(SurfaceId.midi));
      await tester.pumpAndSettle();

      final chain = engine.midiOrNull!.chain;
      final startCount = chain.transforms.length;
      expect(find.byType(TransformChip), findsNWidgets(startCount));

      // Open the `+` menu and add a built-in from the catalogue.
      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('transpose · +12 st'));
      await tester.pumpAndSettle();

      expect(chain.transforms, hasLength(startCount + 1));
      expect(chain.transforms.last.label, 'transpose · +12 st');
      expect(
        find.widgetWithText(TransformChip, 'transpose · +12 st'),
        findsOneWidget,
      );

      // Right-click the new chip and remove it via the context menu.
      await tester.tap(
        find.widgetWithText(TransformChip, 'transpose · +12 st'),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('remove'));
      await tester.pumpAndSettle();

      expect(chain.transforms, hasLength(startCount));
      expect(
        find.widgetWithText(TransformChip, 'transpose · +12 st'),
        findsNothing,
      );

      session.dispose();
      await engine.dispose();
    },
  );
}
