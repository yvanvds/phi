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
import '../test/engine/test_doubles/fake_fx_gateway.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_synth_gateway.dart';
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

  // yse 0.2.0 locks the session rate from init to close (issue #443): the
  // stored rate reaches the device only when requested before the engine
  // starts — which boot does from the stored settings (#449) — and a rate
  // picked while Phi runs restarts the audio session in place (#448), with the
  // shell still bound to the engine's MIDI controllers afterwards.
  testWidgets('the stored sample rate is the running rate; a new pick '
      'restarts the session at it and the shell keeps working', (tester) async {
    final gateway = FakeYseGateway()..devices = const [_alpha, _beta];
    final midi = FakeMidiGateway();
    final engine = PhiEngine(
      gateway,
      midiGateway: midi,
      synthGateway: FakeSynthGateway(),
      fxGateway: FakeFxGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final settingsStore = FakeAppSettingsStore(
      const AppSettings(
        audio: AudioSettings(
          outputHost: 'WASAPI',
          outputDevice: 'Alpha',
          sampleRate: 44100,
        ),
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
    // No rate requested here: `PhiApp` reads the stored audio section and boots
    // the engine onto it, rate included (issues #443, #449).
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

    expect(engine.activeAudioSettings?.outputDevice, 'Alpha');
    expect(engine.sessionSampleRate, 44100);
    expect(gateway.activeSampleRate, 44100);
    // The shell captured these in its `initState` (#448).
    final midiController = engine.midi;
    final editor = engine.midi.editor;

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings…'));
    await tester.pumpAndSettle();
    expect(find.textContaining('44100 Hz   ·'), findsOneWidget);

    // Pick 48000 Hz on the rate picker.
    await tester.tap(find.byType(PhiSelect<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('48000 Hz').last);
    await tester.pumpAndSettle();

    // Stored, and running: the session restarted at 48 kHz on Alpha, and the
    // read-back shows it. Before #448 the engine stayed at 44100 until the
    // next launch behind a "next time Phi starts" notice.
    expect(settingsStore.current.audio.sampleRate, 48000);
    expect(engine.sessionSampleRate, 48000);
    expect(gateway.activeSampleRate, 48000);
    expect(engine.activeAudioSettings?.outputDevice, 'Alpha');
    expect(find.textContaining('48000 Hz   ·'), findsOneWidget);
    expect(find.textContaining('next time Phi starts'), findsNothing);

    // The shell is still bound to live controllers, not disposed ones: the
    // transport plays the clip on a fresh engine transport.
    expect(engine.midi, same(midiController));
    expect(engine.midi.editor, same(editor));
    session.play();
    await tester.pump();
    expect(engine.midi.isPlaying, isTrue);
    expect(midi.transports.last.isPlaying, isTrue);
    session.stop();
    await tester.pump();
    expect(tester.takeException(), isNull);

    controller.dispose();
    settings.dispose();
    session.dispose();
    await engine.dispose();
    await midi.dispose();
    await gateway.dispose();
  });
}
