import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/midi/midi_viewport.dart';

import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end smoke test for the workstation shell.
///
/// Drives the real [PhiApp] (real navigation, fonts, layout) backed by a
/// [FakeYseGateway] so no native `libyse.dll` is touched. Exercises the
/// default Mix surface — add a channel, arm the engine test signal — then
/// switches surfaces through the left rail and back, asserting the
/// [IndexedStack] swaps the centre region and preserves engine state.
///
/// Replaces the original Phase-1 hello-world test (issue #48), which asserted
/// a `PLAY SINE` button + `PeakMeter` home screen that no longer exists.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) => find.byWidgetPredicate(
    (w) => w is RailButton && w.label == id.label,
  );

  testWidgets('workstation: mix surface, rail switching, state preserved', (
    tester,
  ) async {
    final gateway = FakeYseGateway();
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // Shell chrome + default Mix surface are up. The Mix surface starts with
    // the master channel only (no user channels), so the header reads "1".
    expect(railFor(SurfaceId.mix), findsOneWidget);
    expect(railFor(SurfaceId.midi), findsOneWidget);
    expect(find.text('MIX · 1 CHANNELS'), findsOneWidget);
    expect(find.byType(MidiViewport), findsNothing);

    // Add a user channel via the header '+' button → count goes 1 → 2.
    await tester.tap(find.text('+'));
    await tester.pumpAndSettle();
    expect(find.text('MIX · 2 CHANNELS'), findsOneWidget);

    // Arm the engine's built-in test signal. The label is rendered uppercase
    // by PrimaryButton, so "play sine" → "PLAY SINE" / "STOP SINE".
    expect(find.text('PLAY SINE'), findsOneWidget);
    await tester.tap(find.text('PLAY SINE'));
    await tester.pumpAndSettle();
    expect(gateway.audioTestOn, isTrue);
    expect(engine.testSignal.value, isTrue);
    expect(find.text('STOP SINE'), findsOneWidget);

    // Switch to the MIDI surface via the left rail. The IndexedStack moves
    // the Mix surface offstage (its header is no longer found) and brings
    // the MIDI viewport onstage.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    expect(find.byType(MidiViewport), findsOneWidget);
    expect(find.text('MIX · 2 CHANNELS'), findsNothing);

    // Switch back to Mix. The added channel and the armed test signal are
    // both preserved — engine state outlives the surface swap.
    await tester.tap(railFor(SurfaceId.mix));
    await tester.pumpAndSettle();
    expect(find.text('MIX · 2 CHANNELS'), findsOneWidget);
    expect(find.text('STOP SINE'), findsOneWidget);
    expect(engine.testSignal.value, isTrue);

    session.dispose();
    await engine.dispose();
  });
}
