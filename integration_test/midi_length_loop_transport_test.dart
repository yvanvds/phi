import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
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

/// End-to-end proof of the piano-roll **length authority, loop toggle, and
/// transport row** (issue #190), driven through the real [PhiApp]: the header
/// length field grows the edited clip (persisted into its registry payload), the
/// header loop toggle flips the clip's loop flag (also persisted), and the header
/// transport buttons drive real playback.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  final clipAddress = EntityAddress.parse('clip.phrase_a');

  testWidgets('length field, loop toggle and transport drive the edited clip', (
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

    // Open the MIDI surface — the seeded clip.phrase_a is the edited clip.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();

    ClipDocument storedDocument() => ClipDocument.fromJson(
      (controller.registry.entityAt(clipAddress)!.payload! as Map).cast(),
    );

    final source = engine.midi.editedSession.chain.source;

    // ── Length authority: the bars field grows the clip and persists ──────────
    await tester.enterText(find.byKey(ClipTransportRow.barsFieldKey), '9');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(source.bars, 9);
    expect(storedDocument().source.bars, 9); // written into the payload

    // ── Loop toggle: flips the edited clip's loop flag and persists it ────────
    expect(engine.midi.loop, isTrue); // default on
    await tester.tap(find.byKey(ClipTransportRow.loopKey));
    await tester.pumpAndSettle();

    expect(engine.midi.loop, isFalse);
    expect(storedDocument().loop, isFalse);

    // ── Transport row: play then stop drives the engine transport ─────────────
    await tester.tap(find.byKey(ClipTransportRow.playKey));
    await tester.pump(const Duration(milliseconds: 20));
    expect(engine.midi.isPlaying, isTrue);
    expect(midiGateway.transport, isNotNull);
    expect(midiGateway.transport!.calls, contains('play'));
    // Loop off pushed a non-looping event list (loopBeats <= 0).
    expect(midiGateway.transport!.loopBeats, lessThanOrEqualTo(0));

    await tester.tap(find.byKey(ClipTransportRow.stopKey));
    await tester.pump();
    expect(engine.midi.isPlaying, isFalse);
    expect(midiGateway.transport!.calls, contains('stop'));

    await engine.dispose();
    await midiGateway.dispose();
    controller.dispose();
    appSettings.dispose();
    session.dispose();
  });
}
