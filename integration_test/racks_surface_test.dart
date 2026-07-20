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
import 'package:phi/surfaces/racks/definition_editor_pane.dart';
import 'package:phi/surfaces/racks/definitions_panel.dart';
import 'package:phi/surfaces/racks/voices_pane.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the **Racks surface shell** (issue #209) driven through
/// the real [PhiApp]: a fresh project seeds `synth.sine` and `voice.default` (→
/// `synth.sine` → `mix.master`), so opening the Racks rail entry shows the
/// definitions tree, the voices pane, and — on selection / add — the center
/// editor pane routing. Real navigation, real fonts, real three-pane layout,
/// against in-memory fakes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  final synthSine = EntityAddress.parse('synth.sine');
  final voiceDefault = EntityAddress.parse('voice.default');

  testWidgets('racks surface: rail, three panes, definitions tree, routing', (
    tester,
  ) async {
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

    // The rail carries a Racks entry; open it.
    expect(railFor(SurfaceId.racks), findsOneWidget);
    await tester.tap(railFor(SurfaceId.racks));
    await tester.pumpAndSettle();

    // Left pane: the seeded synth definition renders in the SYNTHS tree.
    expect(find.text('SYNTHS'), findsOneWidget);
    expect(find.text('EFFECTS'), findsOneWidget);
    expect(find.byKey(DefinitionsPanel.rowKey(synthSine)), findsOneWidget);

    // Right pane: the seeded voice renders (sine → master).
    expect(find.text('VOICES'), findsOneWidget);
    expect(find.byKey(VoicesPane.rowKey(voiceDefault)), findsOneWidget);
    expect(find.textContaining('sine → master'), findsOneWidget);

    // Center pane starts empty until a definition is selected.
    expect(find.byKey(DefinitionEditorPane.emptyKey), findsOneWidget);

    // Selecting the seeded synth routes the editor pane.
    await tester.tap(find.byKey(DefinitionsPanel.rowKey(synthSine)));
    await tester.pumpAndSettle();
    expect(find.byKey(DefinitionEditorPane.titleKey), findsOneWidget);
    expect(find.text('synth · sine'), findsOneWidget);

    // Adding a VA synth through the header + menu lands it in the registry and
    // routes the editor to it.
    await tester.tap(find.byKey(DefinitionsPanel.synthAddKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(DefinitionsPanel.addItemKey('synth', 'va')));
    await tester.pumpAndSettle();
    final synthVa = EntityAddress.parse('synth.va');
    expect(controller.registry.contains(synthVa), isTrue);
    expect(find.text('synth · va'), findsOneWidget);

    await engine.dispose();
    controller.dispose();
    appSettings.dispose();
    session.dispose();
  });
}
