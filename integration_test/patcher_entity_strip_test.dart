import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/shell/project/project_menu.dart';
import 'package:phi/surfaces/patcher/library/patch_entity_strip.dart';
import 'package:phi/surfaces/patcher/placement/patch_placement_bar.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the patcher **entity strip + source-on-bus placement UI**
/// (issue #224) through the real [PhiApp] — real rail navigation, layout, and
/// fonts — backed by a [FakePatcherGateway] so no native `libyse.dll` is touched.
///
/// Two user-visible flows: switching which `patch.` entity is open (create a
/// second patch, switch between them — cleanly, no instance leaks) and placing
/// the open patch on a mix bus then starting / stopping it; plus a save/reload
/// round-trip proving the placement persists.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  EntityAddress patch(String name) =>
      EntityAddress(kind: RegistryKinds.patch, segments: [name]);
  final master = EntityAddress(
    kind: RegistryKinds.mix,
    segments: const ['master'],
  );

  testWidgets('switch patches, place a source on master, start then stop', (
    tester,
  ) async {
    final patcherGateway = FakePatcherGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      patcherGateway: patcherGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // Summon the Patcher surface — the engine seeded + opened a default patch.
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    final library = engine.patchLibrary;
    final first = library.openAddress!;
    // One default patch → exactly one native instance so far.
    expect(patcherGateway.instances, hasLength(1));

    // Expand the entity strip and add a second patch — it opens.
    await tester.tap(find.byKey(PatchEntityStrip.expandToggleKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PatchEntityStrip.addMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('new patch'));
    await tester.pumpAndSettle();

    final second = library.openAddress!;
    expect(second, isNot(first));
    // Two patch entities → two instances, no leaks from the switch.
    expect(patcherGateway.instances, hasLength(2));

    // Switch back to the first, then to the second — cleanly, no new instances.
    await tester.tap(find.byKey(PatchEntityStrip.rowKey(first)));
    await tester.pumpAndSettle();
    expect(library.openAddress, first);
    await tester.tap(find.byKey(PatchEntityStrip.rowKey(second)));
    await tester.pumpAndSettle();
    expect(library.openAddress, second);
    expect(patcherGateway.instances, hasLength(2));

    // Place the open patch on master via the placement bar.
    await tester.tap(find.byKey(PatchPlacementBar.placeSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('master').last);
    await tester.pumpAndSettle();
    expect(library.placementOf(second), master);

    // Start → the source mounts on master (null channel id) through the gateway.
    final id = engine.patches.instanceIdOf(second);
    await tester.tap(find.byKey(PatchPlacementBar.startStopKey));
    await tester.pumpAndSettle();
    expect(library.isRunning(second), isTrue);
    expect(patcherGateway.calls, contains('mountAsSource:$id:null:1.000'));

    // Stop → it unmounts.
    await tester.tap(find.byKey(PatchPlacementBar.startStopKey));
    await tester.pumpAndSettle();
    expect(library.isRunning(second), isFalse);
    expect(patcherGateway.calls, contains('unmountSource:$id'));

    session.dispose();
    await engine.dispose();
  });

  testWidgets('a bus placement persists across a save/reload', (tester) async {
    const dir = '/projects/patch_place.phi';
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    // --- Launch 1: place the open patch on master, save --------------------
    final patcher1 = FakePatcherGateway();
    final engine1 = PhiEngine(
      FakeYseGateway(),
      patcherGateway: patcher1,
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session1 = SessionState();
    final appSettings1 = AppSettingsController(settings);
    final controller1 = ProjectController(
      session: session1,
      settings: appSettings1,
      storeFactory: (_) => store,
      journalStoreFactory: (_) => journal,
      autosaveIntervalOverride: const Duration(hours: 1),
    );

    await tester.pumpWidget(
      PhiApp(
        key: const ValueKey('launch-1'),
        engine: engine1,
        session: session1,
        projectController: controller1,
        directoryPicker: FakeProjectDirectoryPicker(newLocationPath: dir),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    final open = engine1.patchLibrary.openAddress!;

    // Place on master via the placement bar (dirties the project).
    await tester.tap(find.byKey(PatchPlacementBar.placeSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('master').last);
    await tester.pumpAndSettle();
    expect(engine1.patchLibrary.placementOf(open), master);
    expect(controller1.isDirty.value, isTrue);

    // Save through the File menu.
    await tester.tap(
      find.descendant(
        of: find.byType(ProjectMenu),
        matching: find.text('untitled'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller1.isDirty.value, isFalse);

    // --- Launch 2: reopen, expect the placement restored ------------------
    final patcher2 = FakePatcherGateway();
    final engine2 = PhiEngine(
      FakeYseGateway(),
      patcherGateway: patcher2,
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session2 = SessionState();
    final appSettings2 = AppSettingsController(settings);
    final controller2 = ProjectController(
      session: session2,
      settings: appSettings2,
      storeFactory: (_) => store,
      journalStoreFactory: (_) => journal,
      autosaveIntervalOverride: const Duration(hours: 1),
    );

    await tester.pumpWidget(
      PhiApp(
        key: const ValueKey('launch-2'),
        engine: engine2,
        session: session2,
        projectController: controller2,
        directoryPicker: FakeProjectDirectoryPicker(),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    await engine1.dispose();
    controller1.dispose();
    appSettings1.dispose();
    session1.dispose();

    // The reloaded patch carries its placement, and the reconciler restored it.
    final restored = PatchPayload.fromJson(
      (controller2.registry.entityAt(open)!.payload! as Map).cast(),
    );
    expect(restored.placement, master);
    expect(engine2.patchLibrary.placementOf(open), master);
    // Running state does not persist — a loaded project starts silent.
    expect(engine2.patchLibrary.isRunning(open), isFalse);

    // The reopened patch is the same address the first launch placed.
    expect(open, patch(open.name));

    await engine2.dispose();
    controller2.dispose();
    appSettings2.dispose();
    session2.dispose();
  });
}
