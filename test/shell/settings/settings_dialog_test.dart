import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/app_settings/app_settings.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/engine/bridge/audio_device_descriptor.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/settings/settings_dialog.dart';

import '../../domain/project/test_doubles/fake_app_settings_store.dart';
import '../../engine/test_doubles/fake_yse_gateway.dart';

const _alpha = AudioDeviceDescriptor(
  name: 'Alpha',
  hostName: 'WASAPI',
  sampleRates: [44100.0, 48000.0],
  bufferSizes: [128, 256],
  defaultBufferSize: 256,
  outputLatency: 256,
);

void main() {
  late FakeYseGateway gateway;
  late PhiEngine engine;
  late FakeAppSettingsStore store;
  late AppSettingsController settings;

  setUp(() async {
    gateway = FakeYseGateway()..devices = const [_alpha];
    engine = PhiEngine(gateway, telemetryInterval: const Duration(days: 1));
    engine.start();
    engine.switchAudioDevice(
      const AudioSettings(outputHost: 'WASAPI', outputDevice: 'Alpha'),
    );
    store = FakeAppSettingsStore(
      const AppSettings(
        audio: AudioSettings(outputHost: 'WASAPI', outputDevice: 'Alpha'),
      ),
    );
    settings = AppSettingsController(store);
    await settings.load();
  });

  tearDown(() async {
    settings.dispose();
    await engine.dispose();
    await gateway.dispose();
  });

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsDialog(engine: engine, settings: settings),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists all four sections and opens on AUDIO', (tester) async {
    await pumpDialog(tester);

    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('AUDIO'), findsOneWidget);
    expect(find.text('MIDI'), findsOneWidget);
    expect(find.text('PROJECTS'), findsOneWidget);
    expect(find.text('DIAGNOSTICS'), findsOneWidget);
    // AUDIO is the default section, so its fields are on screen.
    expect(find.text('OUTPUT DEVICE'), findsOneWidget);
  });

  testWidgets('selecting another section swaps the right pane', (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text('MIDI'));
    await tester.pumpAndSettle();

    // The AUDIO fields are gone and the MIDI section's fields show instead.
    expect(find.text('OUTPUT DEVICE'), findsNothing);
    expect(find.text('OUTPUT PORT'), findsOneWidget);
    expect(find.text('INPUT PORTS'), findsOneWidget);
  });

  testWidgets('the close button dismisses the dialog', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => SettingsDialog.show(
                  context,
                  engine: engine,
                  settings: settings,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('SETTINGS'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('SETTINGS'), findsNothing);
  });
}
