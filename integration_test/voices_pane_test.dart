import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/domain/voice/voice_kind.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/midi/piano_roll_editor.dart';
import 'package:phi/surfaces/racks/voices_pane.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_fx_gateway.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_synth_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the **Voices pane** (issue #211, design
/// `docs/design/racks-and-voices.md` §7, §8) driven through the real [PhiApp]:
/// a fresh project seeds `voice.default` → `synth.sine` → master, which the
/// engine materialises on a [FakeSynthGateway]. So arming that voice and pressing
/// the on-screen test strip sounds its real materialised synth, and clicking a
/// note in the piano roll previews it through the routed voice — all through real
/// navigation, fonts and layout against in-memory fakes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  final voiceDefault = EntityAddress.parse('voice.default');

  ({
    PhiEngine engine,
    SessionState session,
    AppSettingsController appSettings,
    ProjectController controller,
    FakeSynthGateway synths,
  })
  buildApp() {
    final synths = FakeSynthGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: FakeMidiGateway(),
      synthGateway: synths,
      fxGateway: FakeFxGateway(),
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
    return (
      engine: engine,
      session: session,
      appSettings: appSettings,
      controller: controller,
      synths: synths,
    );
  }

  testWidgets('voices pane: arm + test-strip audition, then kind switch', (
    tester,
  ) async {
    final app = buildApp();
    await tester.pumpWidget(
      PhiApp(
        engine: app.engine,
        session: app.session,
        projectController: app.controller,
        directoryPicker: FakeProjectDirectoryPicker(),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    // Open the Racks surface; the seeded voice renders its editable card.
    await tester.tap(railFor(SurfaceId.racks));
    await tester.pumpAndSettle();
    expect(find.byKey(VoicesPane.rowKey(voiceDefault)), findsOneWidget);

    // The engine materialised the seeded internal voice onto the fake synth
    // gateway — the handle the audition path drives.
    final synth = app.synths.synths.single;

    // Arm the voice, then press a test-strip key: its materialised synth sounds.
    await tester.tap(find.byKey(VoicesPane.armKey(voiceDefault)));
    await tester.pumpAndSettle();
    final key = find.byKey(VoicesPane.testKeyKey(60));
    expect(key, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(key));
    await tester.pump();
    expect(synth.heldNotes, contains(60));
    await gesture.up();
    await tester.pump();
    expect(synth.heldNotes, isEmpty);

    // Disarm, then switch the voice to external — the row swaps to a channel
    // picker and the registry payload flips kind.
    await tester.tap(find.byKey(VoicesPane.armKey(voiceDefault)));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(VoicesPane.kindKey(voiceDefault, VoiceKind.external)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(VoicesPane.channelKey(voiceDefault)), findsOneWidget);
    expect(find.byKey(VoicesPane.synthKey(voiceDefault)), findsNothing);
    final payload =
        app.controller.registry.entityAt(voiceDefault)!.payload as Map;
    expect(payload['kind'], VoiceKind.external.name);

    await app.engine.dispose();
    app.controller.dispose();
    app.appSettings.dispose();
    app.session.dispose();
  });

  testWidgets('roll audition previews a clicked note through its routed voice', (
    tester,
  ) async {
    final app = buildApp();
    await tester.pumpWidget(
      PhiApp(
        engine: app.engine,
        session: app.session,
        projectController: app.controller,
        directoryPicker: FakeProjectDirectoryPicker(),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    // Open the MIDI surface and click in the piano roll: the click previews a
    // note through its routed voice (unrouted → the seeded default voice), so the
    // default voice's materialised synth sounds.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();

    final synth = app.synths.synths.single;
    expect(synth.noteLog, isEmpty);

    await tester.tap(find.byType(PianoRollEditor));
    await tester.pump();

    // A note was auditioned through the routed voice's synth.
    expect(synth.noteLog.where((e) => e.startsWith('on:')), isNotEmpty);

    await app.engine.dispose();
    app.controller.dispose();
    app.appSettings.dispose();
    app.session.dispose();
  });
}
