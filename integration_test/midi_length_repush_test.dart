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
import 'package:phi/surfaces/midi/clip_transport_row.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that editing the edited clip's **length while it is playing**
/// re-pushes the loop window to the engine transport (issue #200), driven through
/// the real [PhiApp].
///
/// A pure length edit (the header `bars` field) moves the clip's declared
/// [MidiClip.totalBeats] without rewriting any note times — so the player's
/// note-list push-on-change (which keys on the interpreted output's identity)
/// never fires. Before the fix the transport's `loopBeats` therefore stayed at
/// the old length until the next play / loop toggle, and the audible loop
/// diverged from the display playhead (which already wraps at the new length).
/// This drives the real header field → editor → session → engine-transport path
/// with a [FakeMidiGateway] recording the pushes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('a mid-play length edit re-pushes the loop window to the engine', (
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

    // Open the MIDI surface — the seeded clip.phrase_a (4 × 4 = 16 beats) is the
    // edited clip, looping on by default.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();

    final source = engine.midi.editedSession.chain.source;
    expect(source.bars, 4);
    expect(engine.midi.loop, isTrue); // loop on — loopBeats tracks the length

    // ── Play the edited clip through the header transport ─────────────────────
    await tester.tap(find.byKey(ClipTransportRow.playKey));
    await tester.pump(const Duration(milliseconds: 20));
    final transport = midiGateway.transport!;
    expect(engine.midi.isPlaying, isTrue);
    // 4 bars × 4 beats = 16 beats declared loop window.
    expect(transport.loopBeats, 16);
    final pushesAfterPlay = transport.pushCount;

    // ── Grow the declared length WHILE PLAYING ────────────────────────────────
    // A pure length edit — no note times rewritten. Use pump (not pumpAndSettle)
    // so the frame ticker runs one advance; the looping playhead never settles.
    await tester.enterText(find.byKey(ClipTransportRow.barsFieldKey), '8');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 20));

    expect(source.bars, 8);
    // The loop window was re-pushed to the engine transport live, not left stale
    // at 16 — 8 bars × 4 beats = 32 beats.
    expect(
      transport.loopBeats,
      32,
      reason: 'the mid-play length edit re-pushed the loop window',
    );
    expect(transport.pushCount, greaterThan(pushesAfterPlay));

    // ── Stop ──────────────────────────────────────────────────────────────────
    await tester.tap(find.byKey(ClipTransportRow.stopKey));
    await tester.pump();
    expect(engine.midi.isPlaying, isFalse);

    await engine.dispose();
    await midiGateway.dispose();
    controller.dispose();
    appSettings.dispose();
    session.dispose();
  });
}
