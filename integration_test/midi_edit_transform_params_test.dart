import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/midi/transform_chip.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end per-chip parameter edit through the real workstation
/// (issue #71): add a transpose chip, open its context menu's
/// "edit parameters…", type a new semitone count, and see the chain mutate
/// in place — live, while the dialog is still open — against the real shell,
/// real navigation, and the engine's own shared chain.
///
/// The test ends when the dialog closes: under the live integration binding,
/// synthetic pointer input stops registering once a context-menu interaction
/// has fully unwound (issue #96 — reproducible with menu → duplicate alone,
/// so independent of the editor). Cleanup therefore goes through the domain
/// API, and the menu-reopen sequence is covered at the widget level in
/// `test/surfaces/midi/transform_chain_panel_test.dart`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('midi: edit parameters mutates the chip in place, live', (
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

    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();

    final chain = engine.midiOrNull!.chain;
    final startCount = chain.transforms.length;

    // Add a transpose chip to edit.
    await tester.tap(find.text('+'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('transpose · +12 st'));
    await tester.pumpAndSettle();
    expect(chain.transforms, hasLength(startCount + 1));

    // Right-click it and open the parameter editor.
    await tester.tap(
      find.widgetWithText(TransformChip, 'transpose · +12 st'),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('edit parameters…'));
    await tester.pumpAndSettle();

    // The editor shows the chip's current value.
    expect(find.text('semitones'), findsOneWidget);
    expect(find.widgetWithText(TextField, '12'), findsOneWidget);

    // Typing a new value mutates the chip in place while the dialog is open.
    final versionBefore = chain.version;
    await tester.enterText(find.widgetWithText(TextField, '12'), '-12');
    await tester.pump();

    final edited = chain.transforms.last as TransposeTransform;
    expect(edited.semitones, -12);
    expect(edited.label, 'transpose · +12 st');
    expect(chain.version, greaterThan(versionBefore));

    await tester.tap(find.text('done'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.widgetWithText(TransformChip, 'transpose · +12 st'),
      findsOneWidget,
    );

    // Clean up through the domain API (issue #96 — see the doc comment).
    chain.removeAt(chain.transforms.length - 1);
    await tester.pumpAndSettle();
    expect(chain.transforms, hasLength(startCount));

    session.dispose();
    await engine.dispose();
  });
}
