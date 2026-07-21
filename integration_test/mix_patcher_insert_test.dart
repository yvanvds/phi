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
import 'package:phi/engine/state/mixer_channel.dart';
import 'package:phi/shell/project/project_menu.dart';
import 'package:phi/surfaces/mix/mix_surface.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_fx_gateway.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_synth_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of a **patcher as an insert effect** (design
/// `docs/design/patcher.md` §4 role 2, issue #225) driven through the real
/// [PhiApp]: the performer picks a project patch from a strip's INSERTS picker,
/// which creates + places its wrapping `fx.` entity (materialised as a
/// `DspObject.patcherInsert` borrowing the live native patcher), the wrapper
/// references the patch **both** ways for delete-impact, and a save/reload
/// restores the insert and its reference. All against in-memory fakes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  EntityAddress fx(String name) =>
      EntityAddress(kind: RegistryKinds.fx, segments: [name]);
  final swirl = EntityAddress(
    kind: RegistryKinds.patch,
    segments: const ['swirl'],
  );

  // The default project plus one unplaced `patch.` entity to insert.
  void seedWithPatch(ProjectRegistry registry) {
    seedDefaultProject(registry);
    registry.createEntity(swirl, payload: PatchPayload.empty.toJson());
  }

  MixerChannel channelNamed(PhiEngine engine, String name) =>
      engine.channels.value.firstWhere((c) => c.name == name);

  testWidgets('a patcher insert places, wires its reference, and round-trips', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const dir = '/projects/mix_patcher_insert.phi';
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    // --- Launch 1: add a strip, insert the patcher, save ---------------------
    final gateway1 = FakeYseGateway();
    final engine1 = PhiEngine(
      gateway1,
      patcherGateway: FakePatcherGateway(),
      midiGateway: FakeMidiGateway(),
      synthGateway: FakeSynthGateway(),
      fxGateway: FakeFxGateway(),
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

    // Add a user strip to host the insert.
    await tester.tap(
      find.descendant(of: find.byType(MixSurface), matching: find.text('+')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('add channel'));
    await tester.pumpAndSettle();
    final ch1 = channelNamed(engine1, 'ch_1');

    // The INSERTS picker offers the patch as a patcher insert; pick it.
    await tester.tap(find.byKey(MixSurface.addInsertKey('ch_1')));
    await tester.pumpAndSettle();
    expect(find.text('patcher · swirl'), findsOneWidget);
    await tester.tap(
      find
          .descendant(
            of: find.byKey(MixSurface.addInsertKey('ch_1')),
            matching: find.text('patcher · swirl'),
          )
          .last,
    );
    await tester.pumpAndSettle();

    // The wrapper is placed and the patch's native instance is live (so the
    // insert borrows it — edits are heard live).
    expect(engine1.channelInserts(ch1), [fx('swirl')]);
    expect(find.byKey(MixSurface.insertRowKey('ch_1', 'swirl')), findsOne);
    expect(engine1.patches.instanceIdOf(swirl), isNotNull);

    // Delete-impact both directions: deleting the patch strands the wrapper,
    // deleting the wrapper strands the inserting bus.
    final chAddress = EntityAddress(
      kind: RegistryKinds.mix,
      segments: [ch1.name],
    );
    expect(
      controller1.registry.impactOfRemoving(swirl).referrers,
      contains(fx('swirl')),
    );
    expect(
      controller1.registry.impactOfRemoving(fx('swirl')).referrers,
      contains(chAddress),
    );

    // Save via the project menu.
    expect(controller1.isDirty.value, isTrue);
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

    // --- Launch 2: reopen; the insert + its reference come back --------------
    final gateway2 = FakeYseGateway();
    final engine2 = PhiEngine(
      gateway2,
      patcherGateway: FakePatcherGateway(),
      midiGateway: FakeMidiGateway(),
      synthGateway: FakeSynthGateway(),
      fxGateway: FakeFxGateway(),
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

    // The insert survived, and its `fx → patch` reference did too — so
    // delete-impact still lists the wrapper after a reload.
    final restored = channelNamed(engine2, 'ch_1');
    expect(engine2.channelInserts(restored), [fx('swirl')]);
    expect(controller2.registry.referencesOf(fx('swirl')), {swirl});
    expect(
      controller2.registry.impactOfRemoving(swirl).referrers,
      contains(fx('swirl')),
    );

    await engine2.dispose();
    await gateway2.dispose();
    controller2.dispose();
    appSettings2.dispose();
    session2.dispose();
  });
}
