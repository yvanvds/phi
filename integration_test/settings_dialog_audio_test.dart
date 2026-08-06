import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/select/phi_select.dart';
import 'package:phi/domain/project/app_settings/app_settings.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/audio_device_descriptor.dart';
import 'package:phi/engine/engine.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that the settings dialog opens from the File menu and its
/// AUDIO section drives the engine's live device switch (issue #154), through the
/// real [PhiApp] against in-memory fakes — the user-visible surface exercised the
/// way a performer reaches it.
const _alpha = AudioDeviceDescriptor(
  name: 'Alpha',
  hostName: 'WASAPI',
  sampleRates: [44100.0, 48000.0],
  bufferSizes: [128, 256],
  defaultBufferSize: 256,
  outputLatency: 256,
);
const _beta = AudioDeviceDescriptor(
  name: 'Beta',
  hostName: 'ASIO',
  sampleRates: [48000.0, 96000.0],
  bufferSizes: [64, 128],
  defaultBufferSize: 64,
  outputLatency: 128,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('open Settings from the File menu and switch the audio device', (
    tester,
  ) async {
    final gateway = FakeYseGateway()..devices = const [_alpha, _beta];
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final settingsStore = FakeAppSettingsStore(
      const AppSettings(
        audio: AudioSettings(outputHost: 'WASAPI', outputDevice: 'Alpha'),
      ),
    );
    final settings = AppSettingsController(settingsStore);
    final controller = ProjectController(
      session: session,
      settings: settings,
      storeFactory: (_) => FakeProjectStore(),
      journalStoreFactory: (_) => FakeJournalStore(),
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

    // Boot opened the stored Alpha device (design §5).
    expect(engine.activeAudioSettings?.outputDevice, 'Alpha');

    // Open the File menu and pick Settings…
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings…'));
    await tester.pumpAndSettle();

    // The dialog is up, on the AUDIO section, showing the current device.
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('OUTPUT DEVICE'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);

    // Switch the output device to Beta through the picker.
    await tester.tap(find.byType(PhiSelect<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();

    // The engine opened Beta live, the read-back reflects it, and the choice
    // was persisted through the single settings owner.
    expect(gateway.openedDevice?.name, 'Beta');
    expect(gateway.openedDevice?.hostName, 'ASIO');
    expect(engine.activeAudioSettings?.outputDevice, 'Beta');
    expect(settings.value.audio.outputDevice, 'Beta');
    expect(settingsStore.current.audio.outputDevice, 'Beta');
    expect(find.textContaining('48000 Hz'), findsOneWidget);

    controller.dispose();
    settings.dispose();
    session.dispose();
    await engine.dispose();
    await gateway.dispose();
  });
}
