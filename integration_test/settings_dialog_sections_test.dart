import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:phi/shell/settings/settings_dialog.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that the settings dialog's MIDI, PROJECTS, and DIAGNOSTICS
/// sections (issue #151) work through the real [PhiApp] against in-memory fakes —
/// the user-visible surfaces exercised the way a performer reaches them.
const _alpha = AudioDeviceDescriptor(
  name: 'Alpha',
  hostName: 'WASAPI',
  sampleRates: [48000.0],
  bufferSizes: [256],
  defaultBufferSize: 256,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('drive the MIDI, PROJECTS and DIAGNOSTICS sections', (
    tester,
  ) async {
    final gateway = FakeYseGateway()
      ..devices = const [_alpha]
      ..engineVersionValue = 'yse-e2e 1.2.3'
      ..libraryPathValue = r'C:\yse\bin';
    final midiGateway = FakeMidiGateway()
      ..deviceNames = const ['loopMIDI Port']
      ..inputNames = const ['Keystation 61', 'Launchpad'];
    final engine = PhiEngine(
      gateway,
      midiGateway: midiGateway,
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

    // Capture clipboard writes for the diagnostics copy button.
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
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

    // Save the project so it becomes a real recent to manage in PROJECTS.
    await controller.saveAs('/projects/night.phi');
    await tester.pumpAndSettle();

    // Open the File menu and pick Settings…
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings…'));
    await tester.pumpAndSettle();
    expect(find.text('SETTINGS'), findsOneWidget);

    // Section labels also appear in the shell chrome behind the modal, so scope
    // the section-list taps to the dialog subtree.
    Finder sectionTile(String label) => find.descendant(
      of: find.byType(SettingsDialog),
      matching: find.text(label),
    );

    // ── MIDI ────────────────────────────────────────────────────────────────
    await tester.tap(sectionTile('MIDI'));
    await tester.pumpAndSettle();

    // Enable a MIDI input — it opens through the gateway and persists.
    await tester.tap(find.text('Keystation 61'));
    await tester.pumpAndSettle();
    expect(midiGateway.openInputNames, contains('Keystation 61'));
    expect(settings.value.midi.inputPorts, contains('Keystation 61'));

    // Pick the output port — it replaces the default and persists.
    await tester.tap(find.byType(PhiSelect<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('loopMIDI Port'));
    await tester.pumpAndSettle();
    expect(engine.midiOutputPort, 'loopMIDI Port');
    expect(settings.value.midi.outputPort, 'loopMIDI Port');

    // ── PROJECTS ──────────────────────────────────────────────────────────────
    await tester.tap(sectionTile('PROJECTS'));
    await tester.pumpAndSettle();
    expect(find.text('night.phi'), findsOneWidget);

    // Pin the recent — it moves into pins and persists.
    await tester.tap(find.byTooltip('pin'));
    await tester.pumpAndSettle();
    expect(settings.value.pinnedProjects, contains('/projects/night.phi'));
    expect(
      settings.value.recentProjects,
      isNot(contains('/projects/night.phi')),
    );

    // ── DIAGNOSTICS ─────────────────────────────────────────────────────────
    await tester.tap(sectionTile('DIAGNOSTICS'));
    await tester.pumpAndSettle();
    expect(find.textContaining('yse-e2e 1.2.3'), findsOneWidget);

    await tester.tap(find.text('copy for bug report'));
    await tester.pumpAndSettle();
    expect(copied, isNotNull);
    expect(copied, contains('libYSE version: yse-e2e 1.2.3'));
    expect(copied, contains('Active device: Alpha · WASAPI'));

    // Close the dialog via its header close button.
    await tester.tap(
      find.descendant(
        of: find.byType(SettingsDialog),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('SETTINGS'), findsNothing);

    // The File menu reflects the pin immediately: the pinned project shows in
    // Open Recent with a pin marker.
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Recent'));
    await tester.pumpAndSettle();
    expect(find.text('night.phi'), findsWidgets);
    expect(find.byIcon(Icons.push_pin), findsWidgets);

    controller.dispose();
    settings.dispose();
    session.dispose();
    await engine.dispose();
    await gateway.dispose();
    await midiGateway.dispose();
  });
}
