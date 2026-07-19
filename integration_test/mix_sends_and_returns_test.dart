import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
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

/// End-to-end proof of the returns section + per-strip sends UI (issue #170)
/// driven through the real [PhiApp]: the performer adds a channel and a return,
/// wires an aux **send** from the channel to the return through the strip's SENDS
/// area (target picker), flips it **pre-fader**, drags its **level** down, and
/// saves — then a second launch pointed at the same project restores the send
/// with the same target, pre/post tap and (lowered) level, and the return still
/// renders in the returns section. All against in-memory fakes, so no native
/// dialog, filesystem or audio hardware is touched.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  EntityAddress mix(List<String> segments) =>
      EntityAddress(kind: RegistryKinds.mix, segments: segments);

  testWidgets('a send + return round-trip a save/reload', (tester) async {
    // A comfortable desktop-sized window so the SENDS area under the strip is
    // fully on-screen for the drag/tap gestures.
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const dir = '/projects/mix_sends.phi';
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    // --- Launch 1: add a channel + return, wire a send, edit it, save --------
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

    // A channel to send from, and a return to send to.
    await addFromMenu('add channel'); // ch_1
    await addFromMenu('add return'); // slugs to return_ (return is reserved)
    expect(engine1.channels.value.map((c) => c.name), ['ch_1']);
    expect(engine1.returns.value.map((c) => c.name), ['return_']);
    // The return renders in the returns section beside master.
    expect(find.byKey(MixSurface.returnsSectionKey), findsOneWidget);

    // Wire a send from ch_1 to the return through the add-send picker. The
    // option is scoped to the picker's own subtree so it never collides with the
    // return name shown in the returns-section strip.
    await tester.tap(find.byKey(MixSurface.addSendKey('ch_1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byKey(MixSurface.addSendKey('ch_1')),
            matching: find.text('return_'),
          )
          .last,
    );
    await tester.pumpAndSettle();

    final ch1 = engine1.channels.value.single;
    expect(engine1.channelSends(ch1), hasLength(1));
    expect(engine1.channelSends(ch1).single.to, mix(['return_']));
    expect(engine1.channelSends(ch1).single.preFader, isFalse);

    // Flip it pre-fader.
    await tester.tap(find.byKey(MixSurface.sendPrePostKey('ch_1', 0)));
    await tester.pumpAndSettle();
    expect(engine1.channelSends(ch1).single.preFader, isTrue);

    // Drag the send level down (a gesture-coalesced, ramped edit).
    final fader = find.byKey(MixSurface.sendLevelKey('ch_1', 0));
    final drag = await tester.startGesture(tester.getCenter(fader));
    await tester.pump();
    await drag.moveBy(const Offset(0, 24));
    await tester.pump();
    await drag.moveBy(const Offset(0, 24));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();

    final liveSend = engine1.channelSends(ch1).single;
    expect(liveSend.level, lessThan(1.0)); // dragged down from unity
    final savedLevel = liveSend.level;
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

    // --- Launch 2: reopen; the send + return come back -----------------------
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

    // The return survived and renders in its section again.
    expect(engine2.returns.value.map((c) => c.name), ['return_']);
    expect(find.byKey(MixSurface.returnsSectionKey), findsOneWidget);

    // The send survived with its target, pre-fader tap and lowered level.
    final restoredChannel = engine2.channels.value.single;
    expect(restoredChannel.name, 'ch_1');
    final restoredSend = engine2.channelSends(restoredChannel).single;
    expect(restoredSend.to, mix(['return_']));
    expect(restoredSend.preFader, isTrue);
    expect(restoredSend.level, closeTo(savedLevel, 1e-6));

    await engine2.dispose();
    await gateway2.dispose();
    controller2.dispose();
    appSettings2.dispose();
    session2.dispose();
  });
}
