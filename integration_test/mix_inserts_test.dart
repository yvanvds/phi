import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/fx/fx_definition.dart';
import 'package:phi/domain/fx/fx_kind.dart';
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
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the Mix **INSERTS** area (issue #212, racks design §5)
/// driven through the real [PhiApp]: the performer places fx from the picker onto
/// a strip's insert chain, drags to reorder them, **moves** one onto a second
/// strip behind the impact confirm, and saves — then a second launch pointed at
/// the same project restores each bus's insert chain **in order**. All against
/// in-memory fakes, so no native dialog, filesystem or audio hardware is touched.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  EntityAddress fx(String name) =>
      EntityAddress(kind: RegistryKinds.fx, segments: [name]);

  /// Seeds the default project plus three placeable fx instances, so the mix
  /// strips have effects to insert / reorder / move.
  void seedWithFx(ProjectRegistry registry) {
    seedDefaultProject(registry);
    registry.createEntity(
      fx('big_delay'),
      payload: const FxDefinition(kind: FxKind.lowpassDelay).toJson(),
    );
    registry.createEntity(
      fx('crush'),
      payload: const FxDefinition(kind: FxKind.compressor).toJson(),
    );
    registry.createEntity(
      fx('warble'),
      payload: const FxDefinition(kind: FxKind.phaser).toJson(),
    );
  }

  testWidgets('inserts place, reorder + move and round-trip a save/reload', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const dir = '/projects/mix_inserts.phi';
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    // --- Launch 1: place, reorder + move inserts, then save ------------------
    final gateway1 = FakeYseGateway();
    final engine1 = PhiEngine(
      gateway1,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session1 = SessionState();
    final appSettings1 = AppSettingsController(settings);
    final controller1 = ProjectController(
      session: session1,
      settings: appSettings1,
      storeFactory: (_) => store,
      journalStoreFactory: (_) => journal,
      seedRegistry: seedWithFx,
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

    Future<void> addFromMenu(String item) async {
      await tester.tap(
        find.descendant(of: find.byType(MixSurface), matching: find.text('+')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    Future<void> placeInsert(String channel, String optionLabel) async {
      await tester.tap(find.byKey(MixSurface.addInsertKey(channel)));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byKey(MixSurface.addInsertKey(channel)),
              matching: find.text(optionLabel),
            )
            .last,
      );
      await tester.pumpAndSettle();
    }

    MixerChannel channelNamed(PhiEngine engine, String name) =>
        engine.channels.value.firstWhere((c) => c.name == name);

    // Two strips to move an insert between.
    await addFromMenu('add channel'); // ch_1
    await addFromMenu('add channel'); // ch_2
    expect(engine1.channels.value.map((c) => c.name), ['ch_1', 'ch_2']);

    // Place all three fx onto ch_1 in order.
    await placeInsert('ch_1', 'big_delay');
    await placeInsert('ch_1', 'crush');
    await placeInsert('ch_1', 'warble');
    final ch1 = channelNamed(engine1, 'ch_1');
    expect(engine1.channelInserts(ch1), [
      fx('big_delay'),
      fx('crush'),
      fx('warble'),
    ]);

    // Reorder: drag warble's grip up onto the big_delay row → warble leads.
    final drag = await tester.startGesture(
      tester.getCenter(find.byKey(MixSurface.insertDragKey('ch_1', 'warble'))),
    );
    await tester.pump();
    await drag.moveTo(
      tester.getCenter(
        find.byKey(MixSurface.insertRowKey('ch_1', 'big_delay')),
      ),
    );
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(engine1.channelInserts(ch1), [
      fx('warble'),
      fx('big_delay'),
      fx('crush'),
    ]);

    // Move big_delay onto ch_2 through the picker's impact confirm.
    await tester.tap(find.byKey(MixSurface.addInsertKey('ch_2')));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byKey(MixSurface.addInsertKey('ch_2')),
            matching: find.text('big_delay · on ch_1'),
          )
          .last,
    );
    await tester.pumpAndSettle();
    expect(find.text('move insert'), findsOneWidget);
    await tester.tap(find.text('move'));
    await tester.pumpAndSettle();

    final ch2 = channelNamed(engine1, 'ch_2');
    expect(engine1.channelInserts(ch1), [fx('warble'), fx('crush')]);
    expect(engine1.channelInserts(ch2), [fx('big_delay')]);
    expect(controller1.isDirty.value, isTrue);

    // Save via the project menu.
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

    // --- Launch 2: reopen; the insert chains come back in order --------------
    final gateway2 = FakeYseGateway();
    final engine2 = PhiEngine(
      gateway2,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session2 = SessionState();
    final appSettings2 = AppSettingsController(settings);
    final controller2 = ProjectController(
      session: session2,
      settings: appSettings2,
      storeFactory: (_) => store,
      journalStoreFactory: (_) => journal,
      seedRegistry: seedWithFx,
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

    // Both chains survived, each in its saved order.
    final restored1 = channelNamed(engine2, 'ch_1');
    final restored2 = channelNamed(engine2, 'ch_2');
    expect(engine2.channelInserts(restored1), [fx('warble'), fx('crush')]);
    expect(engine2.channelInserts(restored2), [fx('big_delay')]);

    await engine2.dispose();
    await gateway2.dispose();
    controller2.dispose();
    appSettings2.dispose();
    session2.dispose();
  });
}
