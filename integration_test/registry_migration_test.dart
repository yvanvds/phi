import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/channel_strip/channel_strip.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/project/project_menu.dart';
import 'package:phi/surfaces/mix/mix_surface.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the v1 entity migration (issue #124) driven through the
/// real [PhiApp]: a fresh project is seeded with the demo clip + time domains,
/// the performer adds a mix channel through the Mix surface, saves — and a
/// second launch pointed at the same project restores the whole state (the
/// channel materialises from its `mix.` entity; the clip and domain entities are
/// back in the registry). All against in-memory fakes, so no native dialog or
/// filesystem is touched.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mix channel + demo clip + domain round-trip a save/reload', (
    tester,
  ) async {
    const dir = '/projects/live_set.phi';
    // Shared persistence layer both launches see.
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    // --- Launch 1: seed, add a channel, save --------------------------------
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
      seedRegistry: seedDefaultProject,
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

    // A fresh project seeded the demo clip + domain into the live registry.
    expect(
      controller1.registry.contains(EntityAddress.parse('clip.phrase_a')),
      isTrue,
    );
    expect(
      controller1.registry.contains(EntityAddress.parse('domain.drum')),
      isTrue,
    );

    // Add a user channel through the Mix surface '+'.
    final addButton = find.descendant(
      of: find.byType(MixSurface),
      matching: find.text('+'),
    );
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    expect(engine1.channels.value, hasLength(1));
    expect(controller1.isDirty.value, isTrue);

    // Save via the project menu; the new project gets its home from the picker.
    await tester.tap(
      find.descendant(
        of: find.byType(ProjectMenu),
        matching: find.text('untitled'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller1.isSaved, isTrue);
    expect(controller1.isDirty.value, isFalse);

    // --- Launch 2: reopen the same project, expect it fully restored --------
    final gateway2 = FakeYseGateway();
    final engine2 = PhiEngine(
      gateway2,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session2 = SessionState();
    // A fresh owner over the same store — a "restart" reading the saved recents,
    // which auto-restores the saved project.
    final appSettings2 = AppSettingsController(settings);
    final controller2 = ProjectController(
      session: session2,
      settings: appSettings2,
      storeFactory: (_) => store,
      journalStoreFactory: (_) => journal,
      seedRegistry: seedDefaultProject,
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

    // Launch 1 is unmounted now — release its resources.
    await engine1.dispose();
    await gateway1.dispose();
    controller1.dispose();
    appSettings1.dispose();
    session1.dispose();

    // The saved channel materialised from its `mix.` entity …
    expect(engine2.channels.value, hasLength(1));
    expect(engine2.channels.value.single.name, 'ch 1');
    // … and shows on the Mix surface (master + the restored channel).
    expect(find.byType(ChannelStrip), findsNWidgets(2));
    // … and the demo clip + domain entities came back in the registry.
    expect(
      controller2.registry.contains(EntityAddress.parse('clip.phrase_a')),
      isTrue,
    );
    expect(
      controller2.registry.contains(EntityAddress.parse('domain.drum')),
      isTrue,
    );

    await engine2.dispose();
    await gateway2.dispose();
    controller2.dispose();
    appSettings2.dispose();
    session2.dispose();
  });
}
