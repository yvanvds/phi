import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/midi/library/library_panel.dart';
import 'package:phi/surfaces/midi/piano_roll_editor.dart';
import 'package:phi/surfaces/midi/piano_roll_painter.dart';
import 'package:phi/surfaces/midi/velocity_lane_painter.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of piano-roll **panning** (issue #198) driven through the
/// real [PhiApp]: once the roll is zoomed with Ctrl+wheel, a middle-mouse drag
/// pans the shared view, and the velocity lane — which reads the very same view
/// — scrolls in lock-step with the roll.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('middle-drag pans the zoomed roll; the velocity lane follows', (
    tester,
  ) async {
    final midiGateway = FakeMidiGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: midiGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final appSettings = AppSettingsController(FakeAppSettingsStore());
    final controller = ProjectController(
      session: session,
      settings: appSettings,
      storeFactory: (_) => FakeProjectStore(codecs: defaultEntityCodecs()),
      journalStoreFactory: (_) => FakeJournalStore(),
      seedRegistry: seedDefaultProject,
      autosaveIntervalOverride: const Duration(hours: 1),
    );

    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: controller,
        directoryPicker: FakeProjectDirectoryPicker(),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    // Open the MIDI surface and add a fresh clip so the roll is a clean canvas.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(LibraryPanel.expandToggleKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(LibraryPanel.addMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('new clip'));
    await tester.pumpAndSettle();

    final rollRect = tester.getRect(
      find
          .descendant(
            of: find.byType(PianoRollEditor),
            matching: find.byType(CustomPaint),
          )
          .first,
    );

    PianoRollPainter rollPainter() => tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(PianoRollEditor),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((c) => c.painter)
        .whereType<PianoRollPainter>()
        .first;

    VelocityLanePainter velocityPainter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<VelocityLanePainter>()
        .first;

    // ── Zoom in a few ticks so the clip overflows the viewport ────────────────
    // Each Ctrl+wheel-up event magnifies ~1.15×, anchored on the pointer's beat
    // (the roll centre), so the left edge scrolls in and there is room to pan.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final wheel = TestPointer(1, PointerDeviceKind.mouse);
    wheel.hover(rollRect.center);
    for (var i = 0; i < 5; i++) {
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, -120)));
      await tester.pump();
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final zoomed = rollPainter().view;
    expect(zoomed, isNotNull);
    expect(
      zoomed!.scrollBeats,
      greaterThan(0),
    ); // centred zoom left room to pan
    // The velocity lane already shares the zoomed view.
    expect(velocityPainter().view, zoomed);

    // ── Middle-drag right: the content follows the pointer, revealing earlier
    // beats, so the leading-edge scroll shrinks ───────────────────────────────
    final drag = await tester.startGesture(
      rollRect.center,
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await drag.moveBy(const Offset(100, 0));
    await drag.up();
    await tester.pumpAndSettle();

    final panned = rollPainter().view;
    expect(panned, isNotNull);
    expect(panned!.scrollBeats, lessThan(zoomed.scrollBeats));
    expect(panned.scrollBeats, greaterThanOrEqualTo(0));
    // Same zoom, only the scroll moved.
    expect(panned.pixelsPerBeat, zoomed.pixelsPerBeat);
    // The velocity lane scrolled to the exact same place — one shared view.
    expect(velocityPainter().view, panned);

    await engine.dispose();
    await midiGateway.dispose();
    controller.dispose();
    appSettings.dispose();
    session.dispose();
  });
}
