import 'package:flutter/material.dart';
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

/// End-to-end proof of the Mix-surface rename + remove affordances (issue #141)
/// driven through the real [PhiApp]: the performer adds two channels, inline-
/// renames one (which slugs to a new registry address — a `move`, so the address
/// follows the display name), removes the other, and saves. A second launch
/// pointed at the same project restores exactly the surviving, renamed channel —
/// proving the rename and the removal both persisted through a save/reload. All
/// against in-memory fakes, so no native dialog or filesystem is touched.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder stripFor(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(ChannelStrip));

  testWidgets('a rename and a remove round-trip a save/reload', (tester) async {
    const dir = '/projects/mix_edit.phi';
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    // --- Launch 1: add two channels, rename one, remove the other, save ------
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

    // Add two user channels through the Mix surface '+'.
    final addButton = find.descendant(
      of: find.byType(MixSurface),
      matching: find.text('+'),
    );
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    expect(engine1.channels.value.map((c) => c.name), ['ch 1', 'ch 2']);

    // Inline-rename the first strip. 'lead synth' slugs to a new address, so the
    // engine performs a registry move; order preservation keeps it first.
    await tester.tap(find.text('ch 1'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'lead synth');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(engine1.channels.value.map((c) => c.name), ['lead synth', 'ch 2']);
    expect(find.text('lead synth'), findsOneWidget);

    // Remove the second strip via its own header remove control.
    await tester.tap(
      find.descendant(
        of: stripFor('ch 2'),
        matching: find.byKey(ChannelStrip.removeButtonKey),
      ),
    );
    await tester.pumpAndSettle();
    expect(engine1.channels.value.map((c) => c.name), ['lead synth']);
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

    // --- Launch 2: reopen; only the renamed channel survives -----------------
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

    // The removed channel is gone and the renamed one came back with its new
    // name — not the 'ch 1' the seed default would have carried.
    expect(engine2.channels.value.map((c) => c.name), ['lead synth']);
    expect(find.text('lead synth'), findsOneWidget);
    expect(find.text('ch 1'), findsNothing);
    expect(find.text('ch 2'), findsNothing);

    await engine2.dispose();
    await gateway2.dispose();
    controller2.dispose();
    session2.dispose();
  });
}
