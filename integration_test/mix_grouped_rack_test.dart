import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/channel_strip/channel_strip.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_kinds.dart';
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

/// End-to-end proof of the grouped Mix rack (issue #169) driven through the real
/// [PhiApp]: the performer adds a group and two channels from the header `+`
/// menu, **drags** both strips into the group's framed section (re-parenting
/// them), **reorders** them within the section, then saves. A second launch
/// pointed at the same project restores the group with its children in the
/// dragged order — proving the drag-to-group re-parenting *and* the section
/// reorder both persisted through a save/reload. All against in-memory fakes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  EntityAddress mix(List<String> segments) =>
      EntityAddress(kind: RegistryKinds.mix, segments: segments);

  Finder stripFor(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(ChannelStrip));

  Future<void> dragOnto(
    WidgetTester tester,
    Finder source,
    Finder target,
  ) async {
    final gesture = await tester.startGesture(tester.getCenter(source));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('grouping + reorder round-trip a save/reload', (tester) async {
    const dir = '/projects/grouped.phi';
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    // --- Launch 1: add a group + two channels, group them, reorder, save -----
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

    Future<void> addFromMenu(String item) async {
      await tester.tap(
        find.descendant(of: find.byType(MixSurface), matching: find.text('+')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    // Two channels first (ch_1, ch_2), then a group (group).
    await addFromMenu('add channel');
    await addFromMenu('add channel');
    await addFromMenu('add group');
    expect(engine1.channels.value.map((c) => c.name), [
      'ch_1',
      'ch_2',
      'group',
    ]);

    // Drag both channels into the group's framed section (drop on its header).
    await dragOnto(
      tester,
      find.byKey(MixSurface.dragHandleKey('ch_1')),
      stripFor('group'),
    );
    await dragOnto(
      tester,
      find.byKey(MixSurface.dragHandleKey('ch_2')),
      stripFor('group'),
    );
    expect(
      engine1.mixRegistry.childrenOfGroup(mix(['group'])).map((n) => n.name),
      ['ch_1', 'ch_2'],
    );

    // Reorder within the section: drag ch_2 before ch_1.
    await dragOnto(
      tester,
      find.byKey(MixSurface.dragHandleKey('ch_2')),
      stripFor('ch_1'),
    );
    expect(
      engine1.mixRegistry.childrenOfGroup(mix(['group'])).map((n) => n.name),
      ['ch_2', 'ch_1'],
    );
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
    expect(controller1.isDirty.value, isFalse);

    // --- Launch 2: reopen; the group + its dragged child order come back -----
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

    // Release launch 1.
    await engine1.dispose();
    await gateway1.dispose();
    controller1.dispose();
    appSettings1.dispose();
    session1.dispose();

    // The group survived with both children re-parented and in the dragged
    // order — re-parent (file paths) and reorder (_group.json order) both stuck.
    expect(
      engine2.mixRegistry.childrenOfGroup(mix(['group'])).map((n) => n.name),
      ['ch_2', 'ch_1'],
    );
    // The tree the surface renders shows the group with its two children.
    final groupNode = engine2.mixTree.value.firstWhere((n) => n.isGroup);
    expect(groupNode.children.map((c) => c.channel.name), ['ch_2', 'ch_1']);
    // Nothing leaked back to the top level.
    expect(engine2.mixRegistry.contains(mix(['ch_1'])), isFalse);
    expect(engine2.mixRegistry.contains(mix(['ch_2'])), isFalse);

    await engine2.dispose();
    await gateway2.dispose();
    controller2.dispose();
    appSettings2.dispose();
    session2.dispose();
  });
}
