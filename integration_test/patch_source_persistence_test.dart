import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/project/project_menu.dart';
import 'package:yse/yse.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of patch **entity ↔ instance reconciliation + dump-to-payload
/// on save** (issue #220) driven through the real [PhiApp]: a project holding a
/// `patch.` entity materialises a native patcher on open, the performer edits the
/// live patcher, a save flushes that live dump into the entity, and a second
/// launch pointed at the same project **re-materialises the edited patch** (its
/// placement carried through), not the seeded original. All against in-memory
/// fakes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final patchAddress = EntityAddress(
    kind: RegistryKinds.patch,
    segments: const ['swirl'],
  );
  final reverb = EntityAddress(
    kind: RegistryKinds.mix,
    segments: const ['reverb'],
  );

  // A seed that adds one placed `patch.` entity on top of the default project.
  void seedWithPatch(ProjectRegistry registry) {
    seedDefaultProject(registry);
    registry.createEntity(
      patchAddress,
      payload: PatchPayload(placement: reverb).toJson(),
    );
  }

  PatchPayload patchOf(ProjectController controller) => PatchPayload.fromJson(
    (controller.registry.entityAt(patchAddress)!.payload! as Map).cast(),
  );

  /// The `objects` entries of a flushed dump. The engine dump is **structured
  /// and re-parseable** — a list of `{id, type, args, …}` maps, not a summary
  /// count — so a reload can rebuild the graph from it (issue #365).
  List<Map<String, Object?>> objectsOf(PatchPayload payload) => [
    for (final raw in payload.dump['objects']! as List)
      (raw as Map).cast<String, Object?>(),
  ];

  testWidgets('an edited patch round-trips a save/reload, placement intact', (
    tester,
  ) async {
    const dir = '/projects/patch_set.phi';
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    // --- Launch 1: open, edit the live patcher, save -------------------------
    final gateway1 = FakeYseGateway();
    final patcher1 = FakePatcherGateway();
    final engine1 = PhiEngine(
      gateway1,
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
      seedRegistry: seedWithPatch,
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

    // The engine materialised a native patcher for the entity, and it starts
    // unplaced-silent — placement persisted, running state not (loaded silent).
    final instanceId = engine1.patches.instanceIdOf(patchAddress);
    expect(instanceId, isNotNull);
    expect(engine1.patches.placementOf(patchAddress), reverb);
    expect(engine1.patches.isRunning(patchAddress), isFalse);
    // The seeded payload is still empty — nothing has edited the live graph yet.
    expect(patchOf(controller1).dump, isEmpty);

    // Edit the live native patcher (the surface's future seam): add an object.
    // The edit lives in the engine, *not* yet in the entity payload.
    patcher1.createObject(instanceId!, Obj.dSine);
    expect(patchOf(controller1).dump, isEmpty); // dump-on-save, not per-gesture

    // Dirty the project so the save has something to write, then save via the
    // menu — which runs the engine's onBeforeSave flush.
    session1.setTempo(121);
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

    // The save flushed the live dump into the entity (dump-to-payload on save):
    // the one object the performer added, described well enough to rebuild from.
    final flushed = objectsOf(patchOf(controller1));
    expect(flushed, hasLength(1));
    expect(flushed.single['type'], Obj.dSine);

    // --- Launch 2: reopen, expect the edited patch restored ------------------
    final gateway2 = FakeYseGateway();
    final patcher2 = FakePatcherGateway();
    final engine2 = PhiEngine(
      gateway2,
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
      seedRegistry: seedWithPatch,
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

    // Release launch 1.
    await engine1.dispose();
    await gateway1.dispose();
    controller1.dispose();
    appSettings1.dispose();
    session1.dispose();

    // The restored entity carries the edited dump and its placement — the engine
    // re-materialised the *edited* patch from the reloaded payload.
    final restored = patchOf(controller2);
    final restoredObjects = objectsOf(restored);
    expect(restoredObjects, hasLength(1));
    expect(restoredObjects.single['type'], Obj.dSine);
    expect(restored.placement, reverb);
    expect(engine2.patches.isOpen(patchAddress), isTrue);

    // …and the second launch's *native* instance was rebuilt from that dump —
    // the structured form round-trips through `parseJson`, so the edited object
    // is live in the engine, not merely stored in the payload.
    final instanceId2 = engine2.patches.instanceIdOf(patchAddress);
    expect(instanceId2, isNotNull);
    final rebuilt = patcher2.instances[instanceId2]!.nodes;
    expect(rebuilt, hasLength(1));
    expect(rebuilt.values.single.type, Obj.dSine);

    await engine2.dispose();
    await gateway2.dispose();
    controller2.dispose();
    appSettings2.dispose();
    session2.dispose();
  });
}
