import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/fader/phi_fader.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/project/project_menu.dart';
import 'package:phi/shell/right_inspector/right_inspector.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that the **master** strip's state persists (issue #168,
/// design `docs/design/mix.md` §3) driven through the real [PhiApp]: master is
/// not a registry entity, so its volume lives in the project manifest. The
/// performer expands the right inspector, drags the master fader, saves — and a
/// second launch pointed at the same project restores that master volume (and
/// the engine's audio master follows), not the default. All against in-memory
/// fakes, so no native dialog or filesystem is touched.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the master volume round-trips a save/reload', (tester) async {
    const dir = '/projects/master_set.phi';
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    Finder masterFader() => find.descendant(
      of: find.byType(RightInspector),
      matching: find.byType(PhiFader),
    );

    // --- Launch 1: expand the inspector, drag the master fader, save ---------
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

    // Expand the right inspector to reveal the master fader.
    await tester.tap(find.text('INSPECTOR'));
    await tester.pumpAndSettle();

    // Drag the master fader downward (starts at unity, so pull it below 1.0).
    // Start at the track centre — the fader's readout/label sit above/below the
    // draggable track, so a gesture must begin on the track itself — then move
    // down to lower the value.
    final rect = tester.getRect(masterFader());
    final drag = await tester.startGesture(rect.center);
    await drag.moveTo(Offset(rect.center.dx, rect.center.dy + 60));
    await drag.up();
    await tester.pumpAndSettle();

    final savedVolume = session1.masterVolume.value;
    expect(savedVolume, lessThan(0.5)); // dragged down the track
    // The engine's audio master followed the session (mirrored by the shell).
    expect(engine1.masterVolume.value, closeTo(savedVolume, 1e-9));
    expect(gateway1.masterVolumeValue, closeTo(savedVolume, 1e-9));
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

    // --- Launch 2: reopen; the master volume comes back ----------------------
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

    // The restored master volume matches what was saved — not the unity default.
    expect(session2.masterVolume.value, closeTo(savedVolume, 1e-6));
    expect(engine2.masterVolume.value, closeTo(savedVolume, 1e-6));
    // And the engine is *applying* it, not merely reporting it (issue #402).
    // `masterVolume` on the gateway is a cache of the last write, which after a
    // restart can disagree with the gain the master channel actually has; this
    // asserts the audible half, end to end from the reopened project.
    expect(gateway2.appliedMasterVolume, closeTo(savedVolume, 1e-6));

    await engine2.dispose();
    await gateway2.dispose();
    controller2.dispose();
    appSettings2.dispose();
    session2.dispose();
  });
}
