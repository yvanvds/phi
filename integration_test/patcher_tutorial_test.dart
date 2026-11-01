import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_note_box.dart';
import 'package:phi/design/widgets/patcher/patch_toggle_square.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/shell/project/project_menu.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette.dart';
import 'package:phi/surfaces/patcher/patch_canvas_mode.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/placement/patch_placement_bar.dart';
import 'package:phi/surfaces/patcher/reference/patch_reference_panel.dart';
import 'package:phi/surfaces/patcher/tutorial/patch_tutorial_bar.dart';
import 'package:yse/yse.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of **patcher tutorials** (issue #489) through the real
/// [PhiApp] — real rail navigation, real fonts and layout, the **real asset
/// bundle** (`assets/tutorials/patcher/`) and the **real patcher engine**
/// (a [RealPatcherGateway] on an offline libyse session), so the bundled
/// `.metro` tutorial is parsed exactly as it ships. Only the audio device and
/// MIDI are fakes.
///
/// The flow: pick `.metro` in the palette → "Open tutorial" in the reference
/// panel → the tutorial opens read-only with its notes rendered and its
/// `.loadmess` set-up already run, and its toggle starts the metro (whose
/// counter moves) → "Copy to project" → the copy is an ordinary editable
/// patch, an object dropped into it lands, and a save writes it into the
/// project.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: open the metro tutorial from the reference panel, '
      'play it, copy it to the project and save it', (tester) async {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
    addTearDown(System.instance.close);

    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final yse = FakeYseGateway();
    final patcherGateway = RealPatcherGateway();
    final engine = PhiEngine(
      yse,
      patcherGateway: patcherGateway,
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final appSettings = AppSettingsController(FakeAppSettingsStore());
    final project = ProjectController(
      session: session,
      settings: appSettings,
      storeFactory: (_) => store,
      journalStoreFactory: (_) => FakeJournalStore(),
      seedRegistry: seedDefaultProject,
      autosaveIntervalOverride: const Duration(hours: 1),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: project,
        directoryPicker: FakeProjectDirectoryPicker(
          newLocationPath: '/projects/tutorials.phi',
        ),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    final library = engine.patchLibrary;
    expect(
      library.hasTutorial('.metro'),
      isTrue,
      reason: 'the bundled index loaded from the real asset bundle',
    );
    final projectPatch = library.openAddress;
    final patchCount = project.registry
        .childrenOfKind(RegistryKinds.patch)
        .length;

    // ── 1) palette → reference panel → Open tutorial ────────────────────────
    await tester.enterText(find.byKey(PatcherPalette.searchKey), 'metro');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PatcherPalette.entryKey('.metro')));
    await tester.pumpAndSettle();
    expect(find.byKey(PatchReferencePanel.openTutorialKey), findsOneWidget);
    await tester.tap(find.byKey(PatchReferencePanel.openTutorialKey));
    await tester.pumpAndSettle();

    final tutorial = library.tutorial;
    expect(tutorial, isNotNull);
    expect(tutorial!.slug, 'metro');
    expect(find.byKey(PatchTutorialBar.bannerKey), findsOneWidget);
    expect(find.byType(PatchPlacementBar), findsNothing);
    expect(
      tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode,
      PatchCanvasMode.run,
    );

    // Its notes render: the title note and the numbered steps.
    expect(find.byType(PatchNoteBox), findsNWidgets(4));
    expect(
      find.textContaining('A steady pulse', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Click the toggle', findRichText: true),
      findsOneWidget,
    );

    // The `.loadmess 500` set-up ran on load: the interval box reads 500.
    final instance = tutorial.instanceId;
    final graph = patcherGateway.enumerate(instance);
    final numberBoxes = [
      for (final o in graph.objects)
        if (o.type == '.i') o.handleId,
    ];
    expect(
      numberBoxes.map((id) => patcherGateway.guiValue(instance, id)),
      contains(startsWith('500')),
    );

    // ── 2) a GUI control operates: the toggle starts the metro ──────────────
    final toggleId = graph.objects.firstWhere((o) => o.type == '.t').handleId;
    expect(patcherGateway.guiValue(instance, toggleId), 'off');
    await tester.tap(find.byType(PatchToggleSquare));
    await tester.pumpAndSettle();
    expect(
      patcherGateway.guiValue(instance, toggleId),
      'on',
      reason: 'the click reached the real toggle',
    );
    // A metro bangs once the moment it starts — the counter moved.
    expect(
      numberBoxes.map((id) => patcherGateway.guiValue(instance, id)),
      contains(startsWith('1')),
    );
    // Stop it again so nothing ticks on into the copy.
    await tester.tap(find.byType(PatchToggleSquare));
    await tester.pumpAndSettle();

    // Nothing about the tutorial touched the project: no entity was added.
    final copy = EntityAddress.parse('patch.tutorials.metro');
    expect(project.registry.contains(copy.parent!), isFalse);
    expect(
      project.registry.childrenOfKind(RegistryKinds.patch).length,
      patchCount,
    );

    // ── 3) Copy to project → an ordinary, editable patch ────────────────────
    await tester.tap(find.byKey(PatchTutorialBar.copyKey));
    await tester.pumpAndSettle();

    expect(library.tutorial, isNull);
    expect(library.openAddress, copy);
    expect(library.openAddress, isNot(projectPatch));
    expect(find.byType(PatchPlacementBar), findsOneWidget);
    expect(
      tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode,
      PatchCanvasMode.edit,
    );
    expect(find.byType(PatchNoteBox), findsNWidgets(4));
    expect(project.registry.entityAt(copy), isNotNull);
    expect(project.isDirty.value, isTrue);

    // Editable: a palette drop lands in the copy.
    final before = engine.patcher.graph.nodes.length;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(PatcherPalette.entryKey('.metro'))),
    );
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byType(PatcherCanvas)));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(engine.patcher.graph.nodes.length, before + 1);

    // ── 4) …and saved with the project ──────────────────────────────────────
    await tester.tap(
      find.descendant(
        of: find.byType(ProjectMenu),
        matching: find.text('untitled'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(project.isDirty.value, isFalse);

    final saved = PatchPayload.fromJson(
      (project.registry.entityAt(copy)!.payload! as Map).cast(),
    );
    final types = [
      for (final o in saved.dump.values)
        if (o is Map) o['type'],
    ];
    expect(types.where((t) => t == '.metro'), hasLength(2));
    expect(types.where((t) => t == '.text'), hasLength(4));
    expect(jsonEncode(saved.dump), contains('A steady pulse'));

    await tester.pumpWidget(const SizedBox());
    await engine.dispose();
    await yse.dispose();
    project.dispose();
    appSettings.dispose();
    session.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}
