import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/midi/library/library_panel.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the MIDI **library panel** (issue #188) driven through the
/// real [PhiApp]: a fresh project seeds `clip.phrase_a`, so opening the MIDI
/// surface and expanding the panel shows it in the clip tree. From there a new
/// clip is added through the panel (and becomes the edited session), the seeded
/// clip is selected (swapping the editor to it), a row is played (minting its
/// transport on the real engine bridge), and stop-all halts it — all against
/// in-memory fakes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  final phraseA = EntityAddress.parse('clip.phrase_a');

  testWidgets('library panel: tree, selection swap, add, play, stop-all', (
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

    // Open the MIDI surface and expand the (collapsed-by-default) library panel.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(LibraryPanel.expandToggleKey));
    await tester.pumpAndSettle();

    // The seeded clip appears in the tree.
    expect(find.byKey(LibraryPanel.rowKey(phraseA)), findsOneWidget);
    expect(find.text('phrase_a'), findsOneWidget);

    // Add a new clip through the header + menu — it lands in the registry and
    // becomes the edited session.
    await tester.tap(find.byKey(LibraryPanel.addMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('new clip'));
    await tester.pumpAndSettle();
    final newClip = EntityAddress.parse('clip.clip');
    expect(controller.registry.contains(newClip), isTrue);
    expect(engine.midi.editedSession.address, newClip);

    // Selecting the seeded clip swaps the editor's session to it.
    await tester.tap(find.byKey(LibraryPanel.rowKey(phraseA)));
    await tester.pumpAndSettle();
    expect(engine.midi.editedSession.address, phraseA);

    // Play the seeded clip from its row — a transport is minted on its own clock.
    await tester.tap(find.byKey(LibraryPanel.playKey(phraseA)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(engine.midi.sessionFor(phraseA)!.isPlaying, isTrue);
    expect(
      midiGateway.transports.any(
        (t) => t.clockName == 'phi.midi.clip.phrase_a',
      ),
      isTrue,
    );

    // Stop-all in the header halts it.
    await tester.tap(find.byKey(LibraryPanel.stopAllKey));
    await tester.pump(const Duration(milliseconds: 40));
    expect(engine.midi.sessionFor(phraseA)!.isPlaying, isFalse);

    await engine.dispose();
    await midiGateway.dispose();
    controller.dispose();
    appSettings.dispose();
    session.dispose();
  });
}
