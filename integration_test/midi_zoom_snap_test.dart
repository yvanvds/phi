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
import 'package:phi/surfaces/midi/midi_header_strip.dart';
import 'package:phi/surfaces/midi/piano_roll_editor.dart';
import 'package:phi/surfaces/midi/piano_roll_painter.dart';
import 'package:phi/surfaces/midi/snap_grid.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the piano-roll **zoom + snap picker** (issue #189) driven
/// through the real [PhiApp]: opening the MIDI surface on a fresh empty clip, the
/// header snap picker drives `ClipEditor.gridDivision` (and click-to-add follows
/// it), and Ctrl+wheel over the roll magnifies it around the pointer — the
/// painter's live view reflects the new pixels-per-beat.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('snap picker drives the grid; Ctrl+wheel zooms the roll', (
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

    // Open the MIDI surface, then add a fresh (empty) clip so the roll is blank
    // — click-to-add is then unambiguous.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(LibraryPanel.expandToggleKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(LibraryPanel.addMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('new clip'));
    await tester.pumpAndSettle();

    final editor = engine.midi.editedSession.editor;
    expect(editor.clip.notes, isEmpty);

    // ── Snap picker → gridDivision, then click-to-add follows it ──────────────
    // Pick a 1/4 (whole-beat) grid from the header select's overlay.
    await tester.tap(find.byKey(MidiHeaderStrip.snapPickerKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1/4'));
    await tester.pumpAndSettle();
    expect(editor.gridDivision, SnapGrid.quarter);

    // Tap an empty cell on the roll — the added note snaps to the whole-beat grid.
    final rollRect = tester.getRect(
      find
          .descendant(
            of: find.byType(PianoRollEditor),
            matching: find.byType(CustomPaint),
          )
          .first,
    );
    await tester.tapAt(rollRect.center);
    await tester.pumpAndSettle();
    expect(editor.clip.notes, hasLength(1));
    final start = editor.clip.notes.single.start;
    expect(start, closeTo(start.roundToDouble(), 1e-6));

    // Triplet end-to-end: the picker offers 1/8T and it lands on gridDivision.
    await tester.tap(find.byKey(MidiHeaderStrip.snapPickerKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1/8T'));
    await tester.pumpAndSettle();
    expect(editor.gridDivision, SnapGrid.eighthTriplet);

    // ── Ctrl+wheel magnifies the roll around the pointer ──────────────────────
    PianoRollPainter rollPainter() {
      final paints = tester.widgetList<CustomPaint>(
        find.descendant(
          of: find.byType(PianoRollEditor),
          matching: find.byType(CustomPaint),
        ),
      );
      return paints.map((c) => c.painter).whereType<PianoRollPainter>().first;
    }

    // Un-zoomed the painter fits the clip to the width (a null view).
    expect(rollPainter().view, isNull);
    final fitPixelsPerBeat =
        rollRect.width / (rollPainter().bars * rollPainter().beatsPerBar);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(rollRect.center);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final view = rollPainter().view;
    expect(view, isNotNull);
    expect(view!.pixelsPerBeat, greaterThan(fitPixelsPerBeat));

    await engine.dispose();
    await midiGateway.dispose();
    controller.dispose();
    appSettings.dispose();
    session.dispose();
  });
}
