import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/midi/midi_header_strip.dart';
import 'package:phi/surfaces/midi/midi_viewport.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the piano-roll header's responsive `SNAP` label (issue
/// #274), driven through the real [PhiApp] (real fonts, real layout, over
/// fakes). #189 dropped the `SNAP` text label so the already-full header would
/// not overflow at narrow widths; this restores it at roomy widths while
/// keeping it folded away when the pane is tight — the composition the isolated
/// widget test can only approximate with a test font.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('the header SNAP label appears when wide, folds away when narrow', (
    tester,
  ) async {
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    addTearDown(session.dispose);
    addTearDown(engine.dispose);

    // Start with a generously wide window so the MIDI header pane clears the
    // label breakpoint even after the left rail / collapsed library take their
    // share.
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();

    // The MIDI surface is up with its header…
    expect(find.byType(MidiViewport), findsOneWidget);
    // …and, with room to spare, the restored `SNAP` label sits beside the picker.
    expect(find.byKey(MidiHeaderStrip.snapLabelKey), findsOneWidget);
    expect(find.text('SNAP'), findsOneWidget);
    expect(find.byKey(MidiHeaderStrip.snapPickerKey), findsOneWidget);

    // Shrink the window so the header pane drops below the breakpoint. The label
    // folds away, but the picker (and everything else) stays — degrading, not
    // overflowing.
    tester.view.physicalSize = const Size(720, 1000);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(MidiHeaderStrip.snapLabelKey), findsNothing);
    expect(find.text('SNAP'), findsNothing);
    expect(find.byKey(MidiHeaderStrip.snapPickerKey), findsOneWidget);

    // Widening again brings the label back — the behaviour is reversible, not a
    // one-way collapse.
    tester.view.physicalSize = const Size(1800, 1000);
    await tester.pumpAndSettle();
    expect(find.byKey(MidiHeaderStrip.snapLabelKey), findsOneWidget);
  });
}
