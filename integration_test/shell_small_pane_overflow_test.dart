import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/channel_strip/channel_strip.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/domain/shell_layout/drop_edge.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/layout/shell_layout_controller.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/midi/midi_header_strip.dart';
import 'package:phi/surfaces/midi/midi_viewport.dart';
import 'package:phi/surfaces/mix/mix_surface.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that a surface docked into a **small pane** degrades
/// gracefully instead of asserting a `RenderFlex overflowed` (issue #287).
///
/// The #251 dock-move test sidesteps this by sizing its view to 1920x1200 so
/// every pane stays large; that was a workaround, not a fix. These drive the
/// real [PhiApp] (real fonts, real layout, over fakes) at modest window sizes —
/// where a split leaves each pane genuinely small — and assert the two surfaces
/// the issue named come through without overflow: the Mix channel strip shrinks
/// its fader in a short pane, and the MIDI header scrolls in a narrow one.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('Mix strips shrink to fit a short pane without overflowing', (
    tester,
  ) async {
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final layout = ShellLayoutController();
    addTearDown(layout.dispose);

    // A modest, short window: after a column split each pane is only ~half the
    // (already short) height — shorter than a channel strip's natural height,
    // which is exactly what bites at modest window sizes.
    tester.view.physicalSize = const Size(1280, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      PhiApp(engine: engine, session: session, layoutController: layout),
    );
    await tester.pumpAndSettle();

    // Summon MIDI, then dock it below Mix so Mix keeps only the top half.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    layout.split('p1', SurfaceId.midi.name, DropEdge.bottom);
    await tester.pumpAndSettle();

    // Both surfaces render, stacked, in half-height panes…
    expect(layout.layout.paneCount, 2);
    expect(find.byType(MixSurface), findsOneWidget);
    expect(find.byType(MidiViewport), findsOneWidget);

    // The Mix strip degraded by shrinking its fader below the full design
    // height (160) — the concrete evidence the pane was too short for it.
    final faderHeight = tester
        .getSize(find.byKey(ChannelStrip.faderHitAreaKey).first)
        .height;
    expect(faderHeight, lessThan(160));
    expect(faderHeight, greaterThan(0));

    // …and nothing asserted a RenderFlex overflow rendering the short panes.
    expect(tester.takeException(), isNull);

    session.dispose();
    await engine.dispose();
  });

  testWidgets('the MIDI header scrolls in a narrow pane without overflowing', (
    tester,
  ) async {
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final layout = ShellLayoutController();
    addTearDown(layout.dispose);

    // A tall but modestly-wide window: after a row split each pane is only
    // ~half-width, narrower than the MIDI header's content.
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      PhiApp(engine: engine, session: session, layoutController: layout),
    );
    await tester.pumpAndSettle();

    // Summon MIDI, then dock it beside Mix so MIDI gets a half-width pane.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    layout.split('p1', SurfaceId.midi.name, DropEdge.right);
    await tester.pumpAndSettle();

    expect(layout.layout.paneCount, 2);
    expect(find.byType(MixSurface), findsOneWidget);
    expect(find.byType(MidiViewport), findsOneWidget);

    // The header degraded to a horizontal scroll view — its content is wider
    // than the narrow pane, so it scrolls rather than asserting an overflow.
    final headerScroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(MidiHeaderStrip),
        matching: find.byType(Scrollable),
      ),
    );
    expect(headerScroll.position.maxScrollExtent, greaterThan(0));

    expect(tester.takeException(), isNull);

    session.dispose();
    await engine.dispose();
  });
}
