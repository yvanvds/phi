import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/channel_strip/channel_strip.dart';
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

/// End-to-end proof of live mix-state persistence (issue #136) driven through the
/// real [PhiApp]: the performer adds a channel, mutes it, solos it and drags its
/// fader on the Mix surface, saves — and a second launch pointed at the same
/// project restores the channel with the *same* volume, mute and solo, not the
/// defaults. The fader drag exercises the gesture-coalescing path (one persisted
/// command per drag) all the way through the real widget. All against in-memory
/// fakes, so no native dialog or filesystem is touched.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a channel\'s volume/mute/solo round-trip a save/reload', (
    tester,
  ) async {
    const dir = '/projects/mix_set.phi';
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    // --- Launch 1: add a channel, mute + solo + move its fader, save ---------
    final gateway1 = FakeYseGateway();
    final engine1 = PhiEngine(
      gateway1,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session1 = SessionState();
    final controller1 = ProjectController(
      session: session1,
      settingsStore: settings,
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

    // Add a user channel through the Mix surface '+'.
    await tester.tap(
      find.descendant(of: find.byType(MixSurface), matching: find.text('+')),
    );
    await tester.pumpAndSettle();
    expect(engine1.channels.value, hasLength(1));

    // Mute and solo it through the strip's own buttons (only the user strip has
    // them — the master hides M/S), then drag its fader upward.
    await tester.tap(find.text('M'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('S'));
    await tester.pumpAndSettle();

    final userStrip = find.ancestor(
      of: find.text('ch 1'),
      matching: find.byType(ChannelStrip),
    );
    final userFader = find.descendant(
      of: userStrip,
      matching: find.byKey(ChannelStrip.faderHitAreaKey),
    );
    final faderRect = tester.getRect(userFader);
    final drag = await tester.startGesture(
      Offset(faderRect.center.dx, faderRect.bottom - 5),
    );
    await drag.moveTo(Offset(faderRect.center.dx, faderRect.top + 6));
    await drag.up();
    await tester.pumpAndSettle();

    // The live state the performer dialled in — captured to assert the reload
    // restores exactly this.
    final live = engine1.channels.value.single;
    expect(live.muted, isTrue);
    expect(live.soloed, isTrue);
    expect(live.volume, greaterThan(0.8)); // dragged near the top
    final savedVolume = live.volume;
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

    // --- Launch 2: reopen; the channel comes back with its live state --------
    final gateway2 = FakeYseGateway();
    final engine2 = PhiEngine(
      gateway2,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session2 = SessionState();
    final controller2 = ProjectController(
      session: session2,
      settingsStore: settings, // same recents → auto-restores the saved project
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
    session1.dispose();

    // The restored channel carries the saved volume, mute and solo — not the
    // defaults a fresh channel would have.
    final restored = engine2.channels.value.single;
    expect(restored.name, 'ch 1');
    expect(restored.muted, isTrue);
    expect(restored.soloed, isTrue);
    expect(restored.volume, closeTo(savedVolume, 1e-6));

    await engine2.dispose();
    await gateway2.dispose();
    controller2.dispose();
    session2.dispose();
  });
}
