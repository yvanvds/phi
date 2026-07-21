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
import 'package:phi/engine/state/metronome_controller.dart';
import 'package:phi/shell/bottom_status/panic_button.dart';
import 'package:phi/shell/top_toolbar/metronome_control.dart';
import 'package:phi/shell/top_toolbar/top_toolbar.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_midi_transport.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of **panic** (issue #264, design §6) through the real
/// workstation: with the click running and the transport playing, the permanent
/// F12 shortcut — and the status-bar PANIC button — each stop everything (the
/// click, the clip session, and the toolbar transport), against in-memory fakes
/// (no `libyse.dll`, no GL).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the F12 shortcut and the PANIC button stop everything', (
    tester,
  ) async {
    // A performance-sized window so the chrome lays out without overflow.
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final midiGateway = FakeMidiGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: midiGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final controller = ProjectController(
      session: session,
      settings: AppSettingsController(FakeAppSettingsStore()),
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
        directoryPicker: FakeProjectDirectoryPicker(
          newLocationPath: '/projects/panic.phi',
        ),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    FakeMidiTransport click() => midiGateway.transports.firstWhere(
      (t) => t.clockName == MetronomeController.defaultClockName,
    );

    // Enable the click from the toolbar, then start the transport.
    await tester.tap(find.byKey(MetronomeControl.toggleKey));
    await tester.pumpAndSettle();
    expect(engine.metronome.enabled, isTrue);
    expect(click().isPlaying, isTrue);

    await tester.tap(find.byKey(TopToolbar.playKey));
    await tester.pumpAndSettle();
    expect(session.isPlaying, isTrue);
    expect(engine.midi.isPlaying, isTrue);

    // Mash F12 — the permanent panic shortcut, bound through the command registry.
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pumpAndSettle();

    // The click, the clip session, and the toolbar transport all stopped.
    expect(engine.metronome.enabled, isFalse);
    expect(click().isPlaying, isFalse);
    expect(engine.midi.isPlaying, isFalse);
    expect(session.isPlaying, isFalse);

    // The status-bar PANIC button drives the same stop-everything: re-enable the
    // click and re-play, then tap it.
    await tester.tap(find.byKey(MetronomeControl.toggleKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TopToolbar.playKey));
    await tester.pumpAndSettle();
    expect(engine.metronome.enabled, isTrue);
    expect(session.isPlaying, isTrue);

    await tester.tap(find.byKey(PanicButton.buttonKey));
    await tester.pumpAndSettle();
    expect(engine.metronome.enabled, isFalse);
    expect(session.isPlaying, isFalse);
    expect(engine.midi.isPlaying, isFalse);

    session.dispose();
    await engine.dispose();
  });
}
