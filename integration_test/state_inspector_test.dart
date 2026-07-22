import 'package:flutter/gestures.dart';
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
import 'package:phi/domain/state_machine/slices/state_slice_category.dart';
import 'package:phi/domain/state_machine/store/state_document.dart';
import 'package:phi/domain/state_machine/store/state_seed.dart';
import 'package:phi/domain/state_machine/store/state_trigger.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/shell/right_inspector/right_inspector.dart';
import 'package:phi/shell/right_inspector/state_inspector_panel.dart';
import 'package:phi/surfaces/state/state_canvas.dart';
import 'package:phi/surfaces/state/state_transition_badge.dart';
import 'package:phi/surfaces/state/state_trigger_editor.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the state inspector's real SLICES / ON ENTER /
/// TRANSITIONS panels (issue #245) through the real [PhiApp]: capture /
/// per-entry remove / clear mutate the selected state's payload through the
/// journaled commands (with *not captured* vs *captured · empty* rendered
/// distinctly), the ON ENTER picker stores the seeded `code.scratch`, the
/// TRANSITIONS rows edit the trigger and label and add / remove outbound
/// transitions — and the canvas and inspector stay consistent after edits
/// from either side (a trigger edited in the inspector re-badges the canvas;
/// a state authored on the canvas is offered by the inspector's add picker).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Finder onCanvas(String text) =>
      find.descendant(of: find.byType(StateCanvas), matching: find.text(text));

  Finder inInspector(String text) => find.descendant(
    of: find.byType(RightInspector),
    matching: find.text(text),
  );

  StateDocument stateDoc(ProjectController controller, EntityAddress address) {
    final payload = controller.registry.entityAt(address)!.payload!;
    return payload is StateDocument
        ? payload
        : StateDocument.fromJson((payload as Map).cast());
  }

  testWidgets('the inspector panels edit slices, on-enter and transitions '
      'through journaled commands, consistent with the canvas', (tester) async {
    const dir = '/projects/state-inspector.phi';
    final drumDomain = EntityAddress.parse('domain.drum');
    final scratch = EntityAddress.parse('code.scratch');
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    final gateway = FakeYseGateway();
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final appSettings = AppSettingsController(settings);
    final controller = ProjectController(
      session: session,
      settings: appSettings,
      storeFactory: (_) => store,
      journalStoreFactory: (_) => journal,
      seedRegistry: seedDefaultProject,
      autosaveIntervalOverride: const Duration(hours: 1),
    );

    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: controller,
        directoryPicker: FakeProjectDirectoryPicker(newLocationPath: dir),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    // Open the State surface, select `intro`, expand the inspector: the
    // real panels replace the placeholders.
    await tester.tap(railFor(SurfaceId.state));
    await tester.pumpAndSettle();
    await tester.tap(onCanvas('intro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('INSPECTOR'));
    await tester.pumpAndSettle();
    expect(inInspector('state.intro'), findsOneWidget);
    expect(inInspector('SLICES'), findsOneWidget);
    expect(inInspector('ON ENTER'), findsOneWidget);
    expect(inInspector('TRANSITIONS'), findsOneWidget);
    expect(find.text('not captured'), findsNWidgets(4));

    // --- SLICES -------------------------------------------------------------
    // Capture clips with nothing playing: captured-but-empty, meaningfully
    // distinct from not captured ("no clips playing" is a constraint).
    await tester.tap(
      find.byKey(StateInspectorPanel.captureKey(StateSliceCategory.clips)),
    );
    await tester.pumpAndSettle();
    expect(find.text('captured · empty'), findsOneWidget);
    expect(find.text('not captured'), findsNWidgets(3));
    expect(stateDoc(controller, introStateAddress).slices.clips, isEmpty);

    // Shape the live performance: a materialised bus at a set level, muted,
    // plus a runtime variable — then capture mix / variables / tempos.
    final pads = engine.addChannel(name: 'pads');
    engine.setChannelVolume(pads, 0.4);
    engine.setChannelMuted(pads, muted: true);
    engine.runtimeVariables.define(
      name: 'section',
      values: ['a', 'b'],
      current: 'a',
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(StateInspectorPanel.captureKey(StateSliceCategory.mix)),
    );
    await tester.tap(
      find.byKey(StateInspectorPanel.captureKey(StateSliceCategory.variables)),
    );
    await tester.tap(
      find.byKey(StateInspectorPanel.captureKey(StateSliceCategory.tempos)),
    );
    await tester.pumpAndSettle();
    expect(find.text('pads · 0.40 · muted'), findsOneWidget);
    expect(find.text('section = a'), findsOneWidget);
    expect(find.text('drum · 124 bpm'), findsOneWidget);
    final captured = stateDoc(controller, introStateAddress).slices;
    expect(captured.variables, {'section': 'a'});
    expect(captured.tempos, hasLength(1));
    expect(captured.mix, isNotEmpty);

    // Per-entry remove: trimming the only variable keeps the category
    // captured-but-empty — the performer edited the capture down, they did
    // not un-capture it.
    await tester.ensureVisible(
      find.byKey(StateInspectorPanel.removeVariableEntryKey('section')),
    );
    await tester.tap(
      find.byKey(StateInspectorPanel.removeVariableEntryKey('section')),
    );
    await tester.pumpAndSettle();
    expect(find.text('section = a'), findsNothing);
    expect(stateDoc(controller, introStateAddress).slices.variables, isEmpty);
    // clips + variables both captured-empty now.
    expect(find.text('captured · empty'), findsNWidgets(2));

    // Clear clips back to uncaptured.
    await tester.tap(
      find.byKey(StateInspectorPanel.clearKey(StateSliceCategory.clips)),
    );
    await tester.pumpAndSettle();
    expect(find.text('not captured'), findsOneWidget);
    expect(stateDoc(controller, introStateAddress).slices.clips, isNull);

    // --- ON ENTER -----------------------------------------------------------
    await tester.ensureVisible(find.byKey(StateInspectorPanel.onEnterKey));
    await tester.tap(find.byKey(StateInspectorPanel.onEnterKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('code.scratch').last);
    await tester.pumpAndSettle();
    expect(stateDoc(controller, introStateAddress).onEnter, scratch);

    // --- TRANSITIONS --------------------------------------------------------
    // The outbound row shows target + trigger; editing the trigger from the
    // inspector re-badges the canvas (inspector-side edit → canvas).
    final triggerKey = StateInspectorPanel.transitionTriggerKey(
      verseStateAddress,
    );
    await tester.ensureVisible(find.byKey(triggerKey));
    expect(inInspector('→ verse'), findsOneWidget);
    expect(inInspector('manual'), findsOneWidget);
    await tester.tap(find.byKey(triggerKey));
    await tester.pumpAndSettle();
    expect(find.byType(StateTriggerEditor), findsOneWidget);
    await tester.tap(find.byKey(StateTriggerEditor.kindKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('timed').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(StateTriggerEditor.beatsKey), '16');
    await tester.tap(find.byKey(StateTriggerEditor.saveKey));
    await tester.pumpAndSettle();
    expect(
      stateDoc(controller, introStateAddress).transitions.single.trigger,
      TimedTrigger(beats: 16, domain: drumDomain),
    );
    expect(inInspector('timed · 16 beats on drum'), findsOneWidget);
    expect(onCanvas('TIMED'), findsOneWidget);

    // The label inline-edits through the journaled setTransitionLabel.
    final labelKey = StateInspectorPanel.transitionLabelKey(verseStateAddress);
    await tester.ensureVisible(find.byKey(labelKey));
    await tester.tap(find.byKey(labelKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'drop');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      stateDoc(controller, introStateAddress).transitions.single.label,
      'drop',
    );

    // Canvas-side authoring → inspector: a context-menu new state selects
    // it (the inspector follows), and the add picker offers it for intro.
    final origin = tester.getTopLeft(find.byType(StateCanvas));
    await tester.tapAt(
      origin + const Offset(640, 416),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('new state'));
    await tester.pumpAndSettle();
    final added = EntityAddress.parse('state.state');
    expect(controller.registry.contains(added), isTrue);
    expect(inInspector('state.state'), findsOneWidget);

    await tester.tap(onCanvas('intro'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(StateInspectorPanel.addTransitionKey),
    );
    await tester.tap(find.byKey(StateInspectorPanel.addTransitionKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('state').last);
    await tester.pumpAndSettle();
    expect(
      stateDoc(controller, introStateAddress).transitions.map((s) => s.to),
      [verseStateAddress, added],
    );
    expect(find.byType(StateTransitionBadge), findsNWidgets(2));

    // Inspector-side remove → canvas: the verse transition goes, the badge
    // count drops with it.
    await tester.tap(
      find.byKey(StateInspectorPanel.removeTransitionKey(verseStateAddress)),
    );
    await tester.pumpAndSettle();
    expect(
      stateDoc(controller, introStateAddress).transitions.single.to,
      added,
    );
    expect(find.byType(StateTransitionBadge), findsOneWidget);
    expect(onCanvas('TIMED'), findsNothing);

    await engine.dispose();
    await gateway.dispose();
    controller.dispose();
    appSettings.dispose();
    session.dispose();
  });
}
