import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/transforms/velocity_curve_shape.dart';
import 'package:phi/domain/midi/transforms/velocity_to_parameter_transform.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/midi/transform_chip.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end velocity-curve editing through the real workstation (issue #108).
///
/// Adding a `vel → param` chip from the real `+` menu, then opening its typed
/// curve editor from the chip context menu and reshaping the curve — a wider
/// range and an ease-in shape — must land on the engine's own live chain: the
/// transform is re-backed by a declarative [VelocityCurve], so the edit is
/// inspectable, not a lost closure. Proves the catalogue's identity default
/// becomes meaningful through editing alone (the issue's "done when").
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('midi: editing the vel → param chip reshapes the live curve', (
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

    // Navigate to the MIDI surface (the engine owns the shared chain).
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();

    final chain = engine.midiOrNull!.chain;

    // Add a `vel → param` chip from the `+` catalogue menu. The voice section
    // sits below the menu's fold, so scroll the row into view before tapping.
    await tester.tap(find.text('+'));
    await tester.pumpAndSettle();
    final velRow = find.text('vel → param');
    await tester.ensureVisible(velRow);
    await tester.pumpAndSettle();
    await tester.tap(velRow);
    await tester.pumpAndSettle();

    final added = chain.transforms.last as VelocityToParameterTransform;
    // The catalogue default is the identity curve: a soft note passes through.
    expect(
      added
          .eventsFor(const [
            MidiNote(pitch: 60, start: 0, duration: 1, velocity: 0.5),
          ])
          .single
          .value,
      0.5,
    );

    // Right-click the new chip and open its typed curve editor.
    await tester.tap(
      find.widgetWithText(TransformChip, 'vel → param'),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('edit parameters…'));
    await tester.pumpAndSettle();

    // Widen the output range: field [2] is "value @ vel 1".
    final rangeField = find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        )
        .at(2);
    await tester.enterText(rangeField, '100');
    await tester.pump();

    // Switch the shape from linear to exponential (ease-in).
    await tester.tap(find.text('linear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('exponential').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('done'));
    await tester.pumpAndSettle();

    // The live chain now carries the reshaped curve: exponential, 0 → 100.
    final edited = chain.transforms.last as VelocityToParameterTransform;
    expect(edited.curve.shape, VelocityCurveShape.exponential);
    expect(
      edited
          .eventsFor(const [
            MidiNote(pitch: 60, start: 0, duration: 1, velocity: 0.5),
          ])
          .single
          .value,
      25, // 0.5² * 100 — below the linear 50, proving the shape took.
    );

    session.dispose();
    await engine.dispose();
  });
}
