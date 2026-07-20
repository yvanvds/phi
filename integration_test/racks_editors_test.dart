import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/domain/synth/sine_synth.dart';
import 'package:phi/domain/synth/synth_definition.dart';
import 'package:phi/domain/synth/va_synth.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/racks/definition_editor_pane.dart';
import 'package:phi/surfaces/racks/definitions_panel.dart';
import 'package:phi/surfaces/racks/editors/editor_slider_row.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the **Racks per-kind editors** (issue #210) driven
/// through the real [PhiApp]: the seeded `synth.sine` opens its voice-count
/// panel, a fresh VA synth opens the full sectioned panel, and a real slider
/// drag mutates the definition payload — all through real navigation, real
/// fonts, real three-pane layout, against in-memory fakes.
///
/// This exercises the composition an isolated widget test can't: the editor
/// laid out inside the real three-pane surface at a real window size, its edits
/// threading through the live [ProjectController] command layer (so the project
/// goes dirty).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  final synthSine = EntityAddress.parse('synth.sine');
  final synthVa = EntityAddress.parse('synth.va');

  testWidgets('racks editors: sine voice count + VA slider mutate the payload', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: FakeMidiGateway(),
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

    // Open Racks.
    await tester.tap(railFor(SurfaceId.racks));
    await tester.pumpAndSettle();

    // Select the seeded sine synth → its voice-count field renders in the editor.
    await tester.tap(find.byKey(DefinitionsPanel.rowKey(synthSine)));
    await tester.pumpAndSettle();
    expect(find.byKey(DefinitionEditorPane.titleKey), findsOneWidget);
    final voiceField = find.descendant(
      of: find.byType(DefinitionEditorPane),
      matching: find.byType(TextField),
    );
    expect(voiceField, findsOneWidget);

    // Edit the sine voice count end-to-end.
    await tester.enterText(voiceField, '20');
    await tester.pump();
    final sine =
        SynthDefinition.fromJson(
              (controller.registry.entityAt(synthSine)!.payload as Map)
                  .cast<String, Object?>(),
            )
            as SineSynth;
    expect(sine.voiceCount, 20);
    expect(controller.isDirty.value, isTrue);

    // Add a VA synth through the header menu; it auto-selects into the editor.
    await tester.tap(find.byKey(DefinitionsPanel.synthAddKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(DefinitionsPanel.addItemKey('synth', 'va')));
    await tester.pumpAndSettle();

    // The VA panel lays out its sections in the real three-pane surface (the
    // lower sections sit below the ListView fold, so assert the top ones).
    expect(find.text('FILTER'), findsOneWidget);
    expect(find.text('OSC 1'), findsOneWidget);

    // A real drag on the osc-1 detune slider commits a single coalesced edit.
    final detune = find.widgetWithText(EditorSliderRow, 'detune');
    expect(detune, findsOneWidget);
    await tester.drag(detune, const Offset(80, 0));
    await tester.pumpAndSettle();

    final va =
        SynthDefinition.fromJson(
              (controller.registry.entityAt(synthVa)!.payload as Map)
                  .cast<String, Object?>(),
            )
            as VaSynth;
    expect(va.oscillators.first.detune, greaterThan(0));

    await engine.dispose();
    controller.dispose();
    appSettings.dispose();
    session.dispose();
  });
}
