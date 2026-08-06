import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/select/phi_select.dart';
import 'package:phi/domain/project/app_settings/app_settings.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/domain/project/app_settings/speaker_layout.dart';
import 'package:phi/engine/bridge/audio_device_descriptor.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/settings/audio_settings_section.dart';

import '../../domain/project/test_doubles/fake_app_settings_store.dart';
import '../../engine/test_doubles/fake_yse_gateway.dart';

/// Two distinct-named devices under different hosts, so a picker tap is
/// unambiguous and the name+host identity rule (design §3) is exercised.
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
  late FakeYseGateway gateway;
  late PhiEngine engine;
  late FakeAppSettingsStore store;
  late AppSettingsController settings;

  const onAlpha = AudioSettings(outputHost: 'WASAPI', outputDevice: 'Alpha');

  // The engine is booted onto Alpha in setUp — the real (non-fake) zone — so its
  // telemetry timer is a real timer disposed in tearDown, not a fake one the
  // per-test invariant would flag. A far-off telemetry interval keeps the
  // read-back's StreamBuilder from firing frames during the test; the read-back
  // reads activeAudioState() on every build regardless, so liveness is unaffected.
  // Booting onto Alpha establishes the "previous device" a failed switch reverts
  // to (design §9.3).
  setUp(() async {
    gateway = FakeYseGateway()..devices = const [_alpha, _beta];
    engine = PhiEngine(gateway, telemetryInterval: const Duration(days: 1));
    // The app's launch sequence: default device up, then the stored choice
    // applied as a switch (issue #405) — `start` takes no settings.
    engine.start();
    engine.switchAudioDevice(onAlpha);
    store = FakeAppSettingsStore(const AppSettings(audio: onAlpha));
    settings = AppSettingsController(store);
    await settings.load();
  });

  tearDown(() async {
    settings.dispose();
    await engine.dispose();
    await gateway.dispose();
  });

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioSettingsSection(engine: engine, settings: settings),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders every audio field and the active read-back', (
    tester,
  ) async {
    await pumpSection(tester);

    expect(find.text('OUTPUT DEVICE'), findsOneWidget);
    expect(find.text('SAMPLE RATE'), findsOneWidget);
    expect(find.text('BUFFER SIZE'), findsOneWidget);
    expect(find.text('SPEAKER LAYOUT'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    // The stored device shows as the current choice …
    expect(find.text('Alpha'), findsOneWidget);
    // … and the read-back reflects the actually-open device (44100 / 256).
    expect(find.textContaining('44100 Hz'), findsOneWidget);
    expect(find.textContaining('256 frames'), findsOneWidget);
  });

  testWidgets('picking another device applies it live and persists', (
    tester,
  ) async {
    await pumpSection(tester);
    final before = store.saveCount;

    await tester.tap(find.byType(PhiSelect<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();

    // The ASIO Beta (not a WASAPI namesake) was opened live …
    expect(gateway.openedDevice?.name, 'Beta');
    expect(gateway.openedDevice?.hostName, 'ASIO');
    // … the picker now shows it, and the choice was persisted once.
    expect(find.text('Beta'), findsOneWidget);
    expect(settings.value.audio.outputDevice, 'Beta');
    expect(settings.value.audio.outputHost, 'ASIO');
    expect(store.saveCount, greaterThan(before));
  });

  testWidgets('a failed switch reverts the picker and persists nothing', (
    tester,
  ) async {
    gateway.unopenableDeviceNames.add('Beta');
    await pumpSection(tester);
    final before = store.saveCount;

    await tester.tap(find.byType(PhiSelect<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();

    // Reverted to the previous working device (design §9.3): the picker snaps
    // back to Alpha, Beta is not selected, and nothing was written.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
    expect(settings.value.audio.outputDevice, 'Alpha');
    expect(store.saveCount, before);
    // The fallback notice is surfaced.
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('an unplugged interface is still listed, and picking it reverts '
      '(#412)', (tester) async {
    // The list the dropdown is built from is the engine's enumeration cache,
    // filled once inside `init()` and never refreshed — no rescan exists in
    // libyse or its C API (dart-yse #51). So an interface pulled out of the
    // machine goes on being offered, with its old index, and the performer can
    // pick it. This is the shipped shape of the dropdown and it used to be
    // untested: the fake shortened its list on an unplug, so the entry simply
    // vanished and this path never ran.
    gateway.devices = const [_alpha]; // Beta pulled out
    await pumpSection(tester);
    final before = store.saveCount;

    await tester.tap(find.byType(PhiSelect<String>));
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsOneWidget); // still on offer
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();

    // Choosing it is how Phi finds out it is gone: the open fails, the previous
    // working device is reopened, nothing is persisted, and the performer is
    // told — no silent selection of a device that cannot carry audio.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
    expect(settings.value.audio.outputDevice, 'Alpha');
    expect(store.saveCount, before);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    // Audio really is back on Alpha, not merely reported as such.
    expect(engine.activeAudioState().sampleRate, 44100);
  });

  testWidgets('the rate picker is populated from the selected device', (
    tester,
  ) async {
    await pumpSection(tester);

    // Rate is the first int picker (buffer follows it in the column).
    await tester.tap(find.byType(PhiSelect<int>).first);
    await tester.pumpAndSettle();

    // Alpha reports 44100 + 48000, with "device default" as the first entry.
    expect(find.text('44100 Hz'), findsOneWidget);
    expect(find.text('48000 Hz'), findsOneWidget);
    expect(find.text('device default'), findsWidgets);
    // Beta's exclusive rate must not leak in.
    expect(find.text('96000 Hz'), findsNothing);
  });

  testWidgets('changing the speaker layout applies and persists', (
    tester,
  ) async {
    await pumpSection(tester);
    final before = store.saveCount;

    await tester.tap(find.byType(PhiSelect<SpeakerLayout>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quad'));
    await tester.pumpAndSettle();

    expect(gateway.openLayout, SpeakerLayout.quad);
    expect(settings.value.audio.layout, SpeakerLayout.quad);
    expect(store.saveCount, greaterThan(before));
  });
}
