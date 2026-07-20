import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/project/app_settings/app_settings.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/project_manifest.dart';
import 'package:phi/domain/project/store/project_snapshot.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/domain/shell_layout/drop_edge.dart';
import 'package:phi/domain/shell_layout/layout_node.dart';
import 'package:phi/domain/shell_layout/shell_layout.dart';
import 'package:phi/domain/shell_layout/split_axis.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/layout/shell_layout_controller.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/shell/project/project_menu.dart';
import 'package:phi/surfaces/midi/midi_surface.dart';
import 'package:phi/surfaces/mix/mix_surface.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that the **workspace layout** persists in the project
/// manifest (issue #253, design `docs/design/shell-layout.md` §3) driven through
/// the real [PhiApp]: the layout is journal-free workspace arrangement that lives
/// in `project.json`. The performer arranges Mix beside MIDI, saves — and a
/// second launch pointed at the same project restores that split arrangement,
/// not the single-pane seed. A second scenario proves fit-fallback: a set
/// arranged with an extreme splitter fraction opens with the fraction clamped so
/// no pane is unusably thin. All against in-memory fakes — no native dialog,
/// filesystem, GL, or `libyse.dll`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  // The app runs maximized; a split leaves each pane large. Size the test view
  // to match so two side-by-side surfaces both fit (narrow-pane responsiveness
  // is a separate, filed concern — see shell_dock_move_test). The clamp scenario
  // deliberately restores a pane clamped to ~5%, so it uses an extra-wide view
  // to keep even that pane comfortably above the surfaces' usable width — the
  // point under test is the fraction, not narrow-pane rendering.
  void sizeView(WidgetTester tester, {double width = 1920}) {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('the workspace layout round-trips a save/reload', (tester) async {
    const dir = '/projects/layout_set.phi';
    final store = FakeProjectStore(
      codecs: defaultEntityCodecs(),
      groupPayloadKinds: defaultGroupPayloadKinds(),
    );
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();
    sizeView(tester);

    // --- Launch 1: seed single-pane Mix, split MIDI out, save ----------------
    final gateway1 = FakeYseGateway();
    final engine1 = PhiEngine(
      gateway1,
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session1 = SessionState();
    final appSettings1 = AppSettingsController(settings);
    final layout1 = ShellLayoutController();
    addTearDown(layout1.dispose);
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
        layoutController: layout1,
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    // A fresh project seeds the single-pane Mix layout (design §3).
    expect(layout1.layout.paneCount, 1);
    expect(find.byType(MixSurface), findsOneWidget);
    expect(find.byType(MidiSurface), findsNothing);

    // Summon MIDI through the real rail, then dock it into its own pane beside
    // Mix. (The interactive drag lands in #252; drive the layout op directly.)
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    layout1.split('p1', SurfaceId.midi.name, DropEdge.right);
    await tester.pumpAndSettle();

    // Two panes now, Mix beside MIDI — and the rearrange dirtied the manifest.
    expect(layout1.layout.paneCount, 2);
    expect(find.byType(MixSurface), findsOneWidget);
    expect(find.byType(MidiSurface), findsOneWidget);
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

    // --- Launch 2: reopen; the split arrangement comes back ------------------
    final gateway2 = FakeYseGateway();
    final engine2 = PhiEngine(
      gateway2,
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session2 = SessionState();
    final appSettings2 = AppSettingsController(settings);
    final layout2 = ShellLayoutController();
    addTearDown(layout2.dispose);
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
        layoutController: layout2,
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

    // The restored arrangement is the saved two-pane split, not the seed:
    // Mix and MIDI in separate panes, both on screen.
    expect(layout2.layout.paneCount, 2);
    expect(layout2.layout.placedSurfaces, {'mix', 'midi'});
    expect(
      layout2.layout.paneIdOf('midi'),
      isNot(layout2.layout.paneIdOf('mix')),
    );
    expect(find.byType(MixSurface), findsOneWidget);
    expect(find.byType(MidiSurface), findsOneWidget);

    await engine2.dispose();
    await gateway2.dispose();
    controller2.dispose();
    appSettings2.dispose();
    session2.dispose();
  });

  testWidgets('a restored layout clamps an extreme splitter fraction', (
    tester,
  ) async {
    const dir = '/projects/clamp_set.phi';
    final store = FakeProjectStore(
      codecs: defaultEntityCodecs(),
      groupPayloadKinds: defaultGroupPayloadKinds(),
    );
    final journal = FakeJournalStore();
    // Seed the recents so launch restores this project on start.
    final settings = FakeAppSettingsStore(
      const AppSettings(recentProjects: [dir]),
    );
    // Extra-wide: the clamped ~5% pane must still exceed the surfaces' usable
    // width so the assertion is about the fraction, not narrow-pane overflow.
    sizeView(tester, width: 24000);

    // Pre-save a project whose layout has a near-collapsed pane (0.03 of the
    // split) — the kind of geometry a wider screen could produce.
    final extreme = ShellLayout(
      root: LayoutSplit(
        id: 's1',
        axis: SplitAxis.row,
        children: const [
          LayoutPane(id: 'p1', tabs: ['mix'], active: 'mix'),
          LayoutPane(id: 'p2', tabs: ['midi'], active: 'midi'),
        ],
        fractions: const [0.97, 0.03],
      ),
    );
    final seededRegistry = ProjectRegistry();
    seedDefaultProject(seededRegistry);
    await store.save(
      ProjectSnapshot(
        manifest: ProjectManifest(name: 'clamp_set', layout: extreme),
        registry: seededRegistry,
      ),
    );
    seededRegistry.dispose();

    final gateway = FakeYseGateway();
    final engine = PhiEngine(
      gateway,
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final appSettings = AppSettingsController(settings);
    final layout = ShellLayoutController();
    addTearDown(layout.dispose);
    final controller = ProjectController(
      session: session,
      settings: appSettings,
      storeFactory: (_) => store,
      journalStoreFactory: (_) => journal,
      seedRegistry: seedDefaultProject,
      autosaveIntervalOverride: const Duration(hours: 1),
    );

    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: controller,
        directoryPicker: FakeProjectDirectoryPicker(),
        layoutController: layout,
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    // Both surfaces are placed …
    expect(layout.layout.paneCount, 2);
    expect(layout.layout.placedSurfaces, {'mix', 'midi'});

    // … and fit-fallback clamped the near-collapsed 0.03 fraction up to the
    // minimum, so no pane opens unusably thin (design §3).
    final root = layout.layout.root as LayoutSplit;
    final smallest = root.fractions.reduce((a, b) => a < b ? a : b);
    expect(smallest, greaterThan(0.03)); // clamped up from the stored 0.03
    expect(smallest, greaterThanOrEqualTo(ShellLayout.minFraction * 0.9));

    await engine.dispose();
    await gateway.dispose();
    controller.dispose();
    appSettings.dispose();
    session.dispose();
  });
}
