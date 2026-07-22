import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/state_machine/state_node_frame.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/domain/state_machine/state_transition.dart';
import 'package:phi/domain/state_machine/store/state_document.dart';
import 'package:phi/domain/state_machine/store/state_seed.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/shell/project/project_menu.dart';
import 'package:phi/shell/right_inspector/right_inspector.dart';
import 'package:phi/surfaces/state/state_canvas.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the registry-backed state controller + canvas (issue
/// #241) through the real [PhiApp]: the State surface renders the seeded
/// `state.` entities, a node drag journals its position, rename-refactor
/// mid-arm keeps the arm, the canvas context menu authors a new state, and a
/// save + second launch restores the graph, the positions, and the live-state
/// seed (live-ness never persists — it re-seeds on `intro`).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Finder onCanvas(String text) =>
      find.descendant(of: find.byType(StateCanvas), matching: find.text(text));

  StateDocument stateDoc(ProjectController controller, EntityAddress address) {
    final payload = controller.registry.entityAt(address)!.payload!;
    return payload is StateDocument
        ? payload
        : StateDocument.fromJson((payload as Map).cast());
  }

  testWidgets('registry-backed canvas: drag, rename mid-arm, new state, and '
      'a save/reload restoring graph + positions + live seed', (tester) async {
    const dir = '/projects/state-canvas.phi';
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();
    final outro = EntityAddress.parse('state.outro');

    // --- Launch 1 -----------------------------------------------------------
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

    // Open the State surface: the canvas renders the seeded `state.` entities
    // straight from the project registry, live re-seeded on `intro`.
    await tester.tap(railFor(SurfaceId.state));
    await tester.pumpAndSettle();
    expect(find.byType(StateNodeFrame), findsNWidgets(2));
    expect(onCanvas('intro'), findsOneWidget);
    expect(onCanvas('verse'), findsOneWidget);
    expect(find.text('● LIVE'), findsOneWidget);
    expect(engine1.stateMachine.activeStateAddress, introStateAddress);

    // Select `verse` and expand the inspector — the panel shows the entity.
    await tester.tap(onCanvas('verse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('INSPECTOR'));
    await tester.pumpAndSettle();
    expect(find.text('state.verse'), findsOneWidget);

    // Drag the node: transient while the pointer moves, one journaled
    // position command on release — 16px-snapped either way.
    await tester.drag(onCanvas('verse'), const Offset(48, 32));
    await tester.pumpAndSettle();
    final dragged = stateDoc(controller1, verseStateAddress).position;
    expect(dragged, isNot(const Offset(400, 160)));
    expect(dragged.dx % 16, 0);
    expect(dragged.dy % 16, 0);

    // Arm intro → verse, then rename `verse` to `outro` through the
    // inspector: the registry refactor rewrites intro's transition target and
    // the arm follows the address — rename mid-arm keeps the arm (#241
    // done-when).
    engine1.stateMachine.toggleArmed(
      StateTransition(source: introStateAddress, target: verseStateAddress),
    );
    await tester.pumpAndSettle();
    expect(find.text('▲ ARMED · MANUAL'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(RightInspector),
        matching: find.text('verse'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'outro');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(controller1.registry.contains(outro), isTrue);
    expect(controller1.registry.contains(verseStateAddress), isFalse);
    expect(
      stateDoc(controller1, introStateAddress).transitions.single.to,
      outro,
    );
    expect(onCanvas('outro'), findsOneWidget);
    expect(find.text('▲ ARMED · MANUAL'), findsOneWidget);

    // Tap the armed node: the transition fires, `outro` goes live, the arm
    // clears. Firing is performance, not authorship — nothing to save.
    await tester.tap(onCanvas('outro'));
    await tester.pumpAndSettle();
    expect(engine1.stateMachine.activeStateAddress, outro);
    expect(find.text('▲ ARMED · MANUAL'), findsNothing);
    expect(find.text('● LIVE'), findsOneWidget);

    // The canvas context menu authors a third state at the click.
    final origin = tester.getTopLeft(find.byType(StateCanvas));
    await tester.tapAt(
      origin + const Offset(640, 416),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('new state'));
    await tester.pumpAndSettle();
    final added = EntityAddress.parse('state.state');
    expect(controller1.registry.contains(added), isTrue);
    expect(find.byType(StateNodeFrame), findsNWidgets(3));
    final addedPosition = stateDoc(controller1, added).position;

    // Save through the project menu.
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

    // --- Launch 2: the graph, positions, and live seed come back ------------
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

    await tester.tap(railFor(SurfaceId.state));
    await tester.pumpAndSettle();

    // The authored graph and every position round-tripped.
    expect(find.byType(StateNodeFrame), findsNWidgets(3));
    expect(onCanvas('intro'), findsOneWidget);
    expect(onCanvas('outro'), findsOneWidget);
    expect(onCanvas('state'), findsOneWidget);
    expect(
      stateDoc(controller2, introStateAddress).position,
      const Offset(160, 160),
    );
    expect(stateDoc(controller2, outro).position, dragged);
    expect(stateDoc(controller2, added).position, addedPosition);
    expect(
      stateDoc(controller2, introStateAddress).transitions.single.to,
      outro,
    );

    // Live-ness never persisted: the reloaded project re-seeds the live
    // capsule on the first `state.` entity — `intro`, not `outro`.
    expect(engine2.stateMachine.activeStateAddress, introStateAddress);
    expect(find.text('● LIVE'), findsOneWidget);
    expect(find.text('▲ ARMED · MANUAL'), findsNothing);

    await engine2.dispose();
    await gateway2.dispose();
    controller2.dispose();
    appSettings2.dispose();
    session2.dispose();
  });
}
