import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/select/phi_select.dart';
import 'package:phi/domain/project/app_settings/app_settings.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/app_settings/midi_settings.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/settings/midi_settings_section.dart';

import '../../domain/project/test_doubles/fake_app_settings_store.dart';
import '../../engine/test_doubles/fake_midi_gateway.dart';
import '../../engine/test_doubles/fake_yse_gateway.dart';

void main() {
  late FakeYseGateway gateway;
  late FakeMidiGateway midiGateway;
  late PhiEngine engine;
  late FakeAppSettingsStore store;
  late AppSettingsController settings;

  setUp(() async {
    gateway = FakeYseGateway();
    midiGateway = FakeMidiGateway()
      ..deviceNames = const ['loopMIDI Port', 'IAC Bus']
      ..inputNames = const ['Keystation 61', 'Launchpad'];
    engine = PhiEngine(
      gateway,
      midiGateway: midiGateway,
      telemetryInterval: const Duration(days: 1),
    );
    engine.start();
    store = FakeAppSettingsStore(const AppSettings());
    settings = AppSettingsController(store);
    await settings.load();
  });

  tearDown(() async {
    settings.dispose();
    await engine.dispose();
    await gateway.dispose();
    await midiGateway.dispose();
  });

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MidiSettingsSection(engine: engine, settings: settings),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the output picker and a row per input port', (
    tester,
  ) async {
    await pumpSection(tester);

    expect(find.text('OUTPUT PORT'), findsOneWidget);
    expect(find.text('INPUT PORTS'), findsOneWidget);
    // A checklist row per visible input port.
    expect(find.text('Keystation 61'), findsOneWidget);
    expect(find.text('Launchpad'), findsOneWidget);
  });

  testWidgets('picking an output port persists and applies it', (tester) async {
    await pumpSection(tester);
    final before = store.saveCount;

    await tester.tap(find.byType(PhiSelect<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('loopMIDI Port'));
    await tester.pumpAndSettle();

    // Persisted through the single owner and pushed to the engine.
    expect(settings.value.midi.outputPort, 'loopMIDI Port');
    expect(engine.midiOutputPort, 'loopMIDI Port');
    expect(store.saveCount, greaterThan(before));
  });

  testWidgets('checking an input opens it and persists the choice', (
    tester,
  ) async {
    await pumpSection(tester);

    await tester.tap(find.text('Keystation 61'));
    await tester.pumpAndSettle();

    // The port was persisted and opened through the gateway.
    expect(settings.value.midi.inputPorts, contains('Keystation 61'));
    expect(midiGateway.openInputNames, contains('Keystation 61'));

    // Unchecking closes it again.
    await tester.tap(find.text('Keystation 61'));
    await tester.pumpAndSettle();
    expect(settings.value.midi.inputPorts, isNot(contains('Keystation 61')));
    expect(midiGateway.openInputNames, isNot(contains('Keystation 61')));
  });

  testWidgets('a stored, currently-absent output port shows as unavailable', (
    tester,
  ) async {
    await settings.update(
      settings.value.withMidi(const MidiSettings(outputPort: 'Ghost Synth')),
    );
    await pumpSection(tester);

    expect(find.textContaining('Ghost Synth (unavailable)'), findsOneWidget);
  });

  group('MidiActivityDot', () {
    testWidgets('lights only on a matching port emission', (tester) async {
      final controller = StreamController<String>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MidiActivityDot(
                activity: controller.stream,
                portName: 'Keystation 61',
              ),
            ),
          ),
        ),
      );

      Color dotColor() {
        final container = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer),
        );
        return (container.decoration! as BoxDecoration).color!;
      }

      final idle = dotColor();

      // A message on a different port must not light this dot.
      controller.add('Launchpad');
      await tester.pump(); // deliver the broadcast event
      await tester.pump(const Duration(milliseconds: 20)); // rebuild
      expect(dotColor(), idle);

      // A message on this port lights it.
      controller.add('Keystation 61');
      await tester.pump(); // deliver the broadcast event
      await tester.pump(); // rebuild with the lit state
      expect(dotColor(), isNot(idle));

      // It resets after the flash hold.
      await tester.pump(const Duration(milliseconds: 250));
      expect(dotColor(), idle);
    });
  });
}
