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
import 'package:phi/shell/bottom_status/audio_device_chip.dart';
import 'package:phi/shell/diagnostics/notice_center.dart';
import 'package:phi/shell/settings/audio_settings_section.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of Settings › Audio's "Rescan devices" (issue #450),
/// driven through the real [PhiApp]: an interface plugged in while Phi plays
/// on another device is invisible to the dropdown — PortAudio cannot rescan
/// with a stream open — until the performer rescans; then it is listed and
/// one pick opens it.
const _alpha = AudioDeviceDescriptor(
  name: 'Alpha',
  hostName: 'WASAPI',
  sampleRates: [44100.0, 48000.0],
  bufferSizes: [128, 256],
  defaultBufferSize: 256,
  outputLatency: 256,
);
const _gamma = AudioDeviceDescriptor(
  name: 'Gamma',
  hostName: 'ASIO',
  sampleRates: [48000.0, 96000.0],
  bufferSizes: [64, 128],
  defaultBufferSize: 64,
  outputLatency: 128,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an interface plugged in while Alpha plays appears after Rescan '
      'devices and opens with one pick', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final gateway = FakeYseGateway()..devices = const [_alpha];
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 200),
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
    final notices = NoticeCenter.build();

    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: controller,
        directoryPicker: FakeProjectDirectoryPicker(),
        autoStartProject: true,
        noticeCenter: notices,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    expect(engine.activeAudioSettings?.outputDevice, 'Alpha');

    // Gamma is plugged in while Alpha plays.
    gateway.devices = const [_alpha, _gamma];

    await tester.tap(find.byKey(AudioDeviceChip.chipKey));
    await settle();
    expect(find.byType(AudioSettingsSection), findsOneWidget);
    final deviceSelect = find.descendant(
      of: find.byType(AudioSettingsSection),
      matching: find.byType(PhiSelect<String>),
    );

    // Before a rescan the dropdown cannot know about it.
    await tester.tap(deviceSelect);
    await settle();
    expect(find.text('Gamma'), findsNothing);
    await tester.tap(find.text('Alpha').last);
    await settle();

    await tester.tap(find.byKey(AudioSettingsSection.rescanKey));
    await settle();
    expect(engine.activeAudioSettings?.outputDevice, 'Alpha');
    expect(engine.activeAudioState().sampleRate, greaterThan(0));
    expect(settings.value.audio.outputDevice, 'Alpha');

    await tester.tap(deviceSelect);
    await settle();
    expect(find.text('Gamma'), findsOneWidget);
    await tester.tap(find.text('Gamma'));
    await settle();

    expect(engine.activeAudioSettings?.outputDevice, 'Gamma');
    expect(gateway.openedDevice?.hostName, 'ASIO');
    expect(settings.value.audio.outputDevice, 'Gamma');

    notices.dispose();
    controller.dispose();
    settings.dispose();
    session.dispose();
    await engine.dispose();
    await gateway.dispose();
  });
}
