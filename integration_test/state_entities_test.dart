import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/domain/state_machine/store/state_document.dart';
import 'package:phi/domain/state_machine/store/state_seed.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/project/project_menu.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the `state.` entity domain (issue #240) through the
/// real [PhiApp]: a fresh project seeds `state.intro → state.verse` with the
/// transition in the source payload, the seeded edge feeds delete-impact, and
/// a save + second launch round-trips the payloads identically.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The registry-backed state machine (issue #241) normalises loaded
  // map-native payloads to typed [StateDocument]s — accept both forms.
  StateDocument stateDoc(ProjectController controller, EntityAddress address) {
    final payload = controller.registry.entityAt(address)!.payload!;
    return payload is StateDocument
        ? payload
        : StateDocument.fromJson((payload as Map).cast());
  }

  testWidgets('state entities seed, guard delete-impact, and round-trip a '
      'save/reload', (tester) async {
    const dir = '/projects/states.phi';
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    // --- Launch 1: seed + inspect + save ------------------------------------
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

    // The fresh project seeded the default state graph as entities.
    expect(controller1.registry.contains(introStateAddress), isTrue);
    expect(controller1.registry.contains(verseStateAddress), isTrue);

    // The transition rides the source payload: intro → verse, manual trigger,
    // at the canvas position the State surface has always used.
    final intro1 = stateDoc(controller1, introStateAddress);
    expect(intro1.position, const Offset(160, 160));
    expect(intro1.transitions.single.to, verseStateAddress);
    expect(intro1.transitions.single.trigger.kind, 'manual');

    // The transition target feeds the back-reference index: delete-impact on
    // `verse` lists its inbound transition from `intro` (issue #240 done-when).
    final impact = controller1.registry.impactOfRemoving(verseStateAddress);
    expect(impact.referrers, contains(introStateAddress));

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

    final savedIntro = intro1;
    final savedVerse = stateDoc(controller1, verseStateAddress);

    // --- Launch 2: reopen the same project ----------------------------------
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

    // Launch 1 is unmounted now — release its resources.
    await engine1.dispose();
    await gateway1.dispose();
    controller1.dispose();
    appSettings1.dispose();
    session1.dispose();

    // The state entities came back and the payloads round-tripped identity —
    // position, transitions and trigger unchanged (issue #240 done-when).
    expect(stateDoc(controller2, introStateAddress), savedIntro);
    expect(stateDoc(controller2, verseStateAddress), savedVerse);

    // The reloaded transition still feeds delete-impact.
    expect(
      controller2.registry.impactOfRemoving(verseStateAddress).referrers,
      contains(introStateAddress),
    );

    await engine2.dispose();
    await gateway2.dispose();
    controller2.dispose();
    appSettings2.dispose();
    session2.dispose();
  });
}
