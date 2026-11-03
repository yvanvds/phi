import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_bang_square.dart';
import 'package:phi/design/widgets/patcher/patch_list_box.dart';
import 'package:phi/design/widgets/patcher/patch_matrix_grid.dart';
import 'package:phi/design/widgets/patcher/patch_message_box.dart';
import 'package:phi/design/widgets/patcher/patch_note_box.dart';
import 'package:phi/design/widgets/patcher/patch_toggle_square.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/nodes/number_node_body.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette_tab.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:phi/surfaces/patcher/tutorial/patch_tutorial_bar.dart';
import 'package:yse/yse.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';
import '../test/surfaces/patcher/test_support/expect_list_boxes_uncut.dart';
import '../test/surfaces/patcher/test_support/open_tutorial_by_search.dart';
import '../test/surfaces/patcher/test_support/type_into_field.dart';

/// End-to-end proof of the **routing tutorials** (issue #500) through the
/// real [PhiApp]: real rail navigation, fonts and layout, the real asset
/// bundle and the real patcher engine ([RealPatcherGateway] on an offline
/// libyse session). Only the audio device and MIDI are fakes.
///
/// The route-routepass, sel, gate-switch, router-matrix, split,
/// spray-funnel-cycle and bucket-decode tutorials are opened from the
/// palette's Tutorials tab by searching for one of their types. The test
/// checks that the notes render and nothing overlaps, then plays the patches
/// with real taps on message boxes, buttons, toggles and grid cells and real
/// typing into number boxes, and reads the results back from the canvas and
/// the engine, the way the notes tell the user to. None of them makes a sound,
/// so master stays silent throughout.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Finder message(String text) => find.descendant(
    of: find.byType(PatchMessageBox),
    matching: find.text(text),
  );

  testWidgets('patcher: every routing tutorial opens from the Tutorials '
      'tab and does what its notes say', (tester) async {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
    addTearDown(System.instance.close);

    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final yse = FakeYseGateway();
    final gateway = RealPatcherGateway();
    final engine = PhiEngine(
      yse,
      patcherGateway: gateway,
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final appSettings = AppSettingsController(FakeAppSettingsStore());
    final project = ProjectController(
      session: session,
      settings: appSettings,
      storeFactory: (_) => store,
      journalStoreFactory: (_) => FakeJournalStore(),
      seedRegistry: seedDefaultProject,
      autosaveIntervalOverride: const Duration(hours: 1),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 1100));
    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: project,
        directoryPicker: FakeProjectDirectoryPicker(
          newLocationPath: '/projects/routing-tutorials.phi',
        ),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();
    // The first visit leaves the new project's empty patch empty and stopped
    // (#523): nothing is mounted, and master stays silent, so the meter below
    // hears only the tutorials.
    expect(engine.patcher.graph.nodes, isEmpty);
    expect(gateway.isSourceReady(engine.patcher.instanceId), isFalse);
    var idle = 0.0;
    for (var i = 0; i < 400; i++) {
      System.instance
        ..renderOffline(1)
        ..update();
      final p = Channel.master.peakLinearPost();
      if (p > idle) idle = p;
    }
    expect(idle, 0, reason: 'nothing plays before a tutorial opens');
    await tester.tap(
      find.byKey(PatcherPalette.tabKey(PatcherPaletteTab.tutorials)),
    );
    await tester.pumpAndSettle();

    final library = engine.patchLibrary;
    final patchCount = project.registry
        .childrenOfKind(RegistryKinds.patch)
        .length;

    // Opens [type]'s tutorial from the browser and checks the banner, the
    // slug and the notes. Returns a lookup of objects by type and position.
    Future<int Function(String, double, double)> open(
      String type, {
      required String slug,
      required int notes,
      required String heading,
    }) async {
      // Search for the type, the way a user finds it (#524, #527).
      await openTutorialBySearch(tester, type);
      final tutorial = library.tutorial;
      expect(tutorial, isNotNull, reason: type);
      expect(tutorial!.slug, slug);
      expect(find.byKey(PatchTutorialBar.bannerKey), findsOneWidget);
      expect(find.byType(PatchNoteBox), findsNWidgets(notes), reason: slug);
      expect(
        find.textContaining(heading, findRichText: true),
        findsOneWidget,
        reason: '$slug title note',
      );
      // Laid out legibly in the real font: no note or object overlaps
      // another one on the canvas.
      final boxes = [
        for (final e in find.byType(PatcherNodeView).evaluate())
          (
            tester.widget<PatcherNodeView>(find.byWidget(e.widget)).node,
            tester.getRect(find.byWidget(e.widget)),
          ),
      ];
      final overlaps = [
        for (var i = 0; i < boxes.length; i++)
          for (var j = i + 1; j < boxes.length; j++)
            if (boxes[i].$2.overlaps(boxes[j].$2))
              '${boxes[i].$1.type} ${boxes[i].$2} / '
                  '${boxes[j].$1.type} ${boxes[j].$2}',
      ];
      expect(overlaps, isEmpty, reason: '$slug: overlapping nodes');
      // Every tutorial is mounted while open, a silent one too (#528).
      // libyse sets the new sound up on a worker thread, in wall-clock
      // time, while an offline render runs far ahead of real time. Render
      // with real pauses until the sound is in the mix, so that nothing
      // below measures blocks rendered before it joined (#525).
      for (var i = 0; i < 5000; i++) {
        if (gateway.isSourceReady(tutorial.instanceId)) break;
        System.instance
          ..renderOffline(1)
          ..update();
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(
        gateway.isSourceReady(tutorial.instanceId),
        isTrue,
        reason: '$slug joined the mix',
      );
      // And let whatever the last tutorial left ringing drain away.
      for (var i = 0; i < 20; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
      }
      final graph = gateway.enumerate(tutorial.instanceId);
      return (String t, double x, double y) => graph.objects
          .firstWhere((o) => o.type == t && o.position == Offset(x, y))
          .handleId;
    }

    String value(int id) => gateway.guiValue(library.tutorial!.instanceId, id);

    Future<void> tap(Finder f) async {
      expect(f, findsOneWidget);
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    // Closes the tutorial. Back on the project patch, which is still empty
    // and stopped (#523).
    Future<void> close() async {
      // Every list box result the walk-through left must show in full.
      expectListBoxesUncut(
        tester,
        where: engine.patchLibrary.tutorial?.slug ?? '',
      );
      await tap(find.byKey(PatchTutorialBar.closeKey));
      expect(gateway.isSourceReady(engine.patcher.instanceId), isFalse);
    }

    double read(int id) => double.parse(value(id));

    // The canvas view of the [type] object placed at ([x], [y]).
    Finder nodeAt(String type, double x, double y) => find.byWidgetPredicate(
      (w) =>
          w is PatcherNodeView &&
          w.node.type == type &&
          w.node.position == Offset(x, y),
    );

    Finder toggleAt(double x, double y) => find.descendant(
      of: nodeAt('.t', x, y),
      matching: find.byType(PatchToggleSquare),
    );

    // Renders [blocks] blocks of the offline session and returns the loudest
    // master peak among them: what reaches the speakers.
    double loudness([int blocks = 200]) {
      var peak = 0.0;
      for (var i = 0; i < blocks; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
        final p = Channel.master.peakLinearPost();
        if (p > peak) peak = p;
      }
      return peak;
    }

    // The button at ([x], [y]).
    Finder buttonAt(double x, double y) => find.descendant(
      of: nodeAt('.b', x, y),
      matching: find.byType(PatchBangSquare),
    );

    // What the number box at ([x], [y]) shows on the canvas, once the
    // surface's live-value poll has come due.
    Future<double> shown(String type, double x, double y) async {
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: nodeAt(type, x, y),
        matching: find.descendant(
          of: find.byType(NumberNodeBody),
          matching: find.byType(TextField),
        ),
      );
      expect(field, findsOneWidget, reason: '$type at ($x, $y)');
      return double.parse(tester.widget<TextField>(field).controller!.text);
    }

    // Types [text] into the number box at ([x], [y]) and commits it, which
    // sends it on.
    Future<void> typeInto(String type, double x, double y, String text) async {
      final field = find.descendant(
        of: nodeAt(type, x, y),
        matching: find.descendant(
          of: find.byType(NumberNodeBody),
          matching: find.byType(TextField),
        ),
      );
      // Through the shared helper, which survives the window going
      // inactive mid-typing (#544).
      await typeIntoField(tester, field, text, what: '$type at ($x, $y)');
    }

    // Whether a list box on the canvas shows [text] in full, once the
    // live-value poll has come due. A list box cuts a list longer than its
    // width off with an ellipsis, so a tutorial's results must fit the box to
    // be read (issue #533).
    Future<bool> listShows(String text) async {
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      final shown = find.descendant(
        of: find.byType(PatchListBox),
        matching: find.text(text),
      );
      if (shown.evaluate().isEmpty) return false;
      for (final e in shown.evaluate()) {
        expectListTextFits(e);
      }
      return true;
    }

    // Taps the grid cell at [column], [row] of the 2-by-2 matrixctrl and lets
    // the body's poll run.
    Future<void> tapCell(int column, int row) async {
      final box = tester.getRect(find.byType(PatchMatrixGrid));
      await tester.tapAt(
        box.topLeft +
            Offset(
              box.width * (column + 0.5) / 2,
              box.height * (row + 0.5) / 2,
            ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    // ── route and routepass: the first item stripped or kept ────────────────
    var at = await open(
      '.route',
      slug: 'route-routepass',
      notes: 7,
      heading: 'route looks at the first item of every message',
    );
    await tap(message('100'));
    expect(await listShows('60 100'), isTrue, reason: 'the word taken off');
    expect(await listShows('note 60 100'), isTrue, reason: 'routepass keeps');
    await tap(message('64'));
    expect(await listShows('7 64'), isTrue);
    expect(await listShows('ctl 7 64'), isTrue);
    await tap(message('5'));
    await tap(message('5.0'));
    expect(await shown('.i', 280, 410), 2, reason: 'a bang each, 5.0 is 5');
    await tap(message('0.5'));
    expect(value(at('.i', 390, 410)), '1');
    await tap(message('7'));
    expect(await shown('.i', 500, 360), 7, reason: 'route: the rest');
    expect(await shown('.i', 340, 560), 7, reason: 'routepass: the rest');
    await close();

    // ── sel: notes named, the rest passed on, words ─────────────────────────
    at = await open(
      '.sel',
      slug: 'sel',
      notes: 5,
      heading: 'bangs the outlet of the one it matches',
    );
    await tap(message('64'));
    expect(await listShows('E'), isTrue, reason: '64 is E');
    await tap(message('67'));
    expect(await listShows('G'), isTrue);
    await tap(message('61'));
    expect(await shown('.i', 400, 290), 61, reason: 'no match: passed on');
    await typeInto('.i', 500, 160, '60');
    expect(await listShows('C'), isTrue, reason: 'a typed 60');
    expect(value(at('.i', 400, 290)), '61');
    await tap(message('start'));
    expect(value(at('.t', 60, 680)), 'on');
    await tap(message('stop'));
    expect(value(at('.t', 60, 680)), 'off');
    await tap(message('pause'));
    expect(await listShows('pause'), isTrue);
    await close();

    // ── gate and switch: one way through ────────────────────────────────────
    at = await open(
      '.gate',
      slug: 'gate-switch',
      notes: 4,
      heading: 'gate passes what arrives at its right inlet',
    );
    await typeInto('.i', 500, 160, '5');
    expect(
      [
        for (final x in [60.0, 170.0, 280.0]) value(at('.i', x, 290)),
      ],
      ['0', '0', '0'],
      reason: 'closed at first',
    );
    await tap(message('2'));
    await typeInto('.i', 500, 160, '6');
    expect(await shown('.i', 170, 290), 6, reason: 'outlet 2, the middle');
    await tap(message('3'));
    await typeInto('.i', 500, 160, '7');
    expect(await shown('.i', 280, 290), 7);
    await tap(message('0'));
    await typeInto('.i', 500, 160, '8');
    expect(
      [
        for (final x in [60.0, 170.0, 280.0]) value(at('.i', x, 290)),
      ],
      ['0', '6', '7'],
      reason: '0 closes',
    );
    await tap(message('20'));
    expect(value(at('.i', 60, 550)), '0', reason: 'switch starts closed');
    await typeInto('.i', 60, 420, '2');
    await tap(message('10'));
    await tap(message('20'));
    await tap(message('30'));
    expect(await shown('.i', 60, 550), 20, reason: 'only inlet 2 passes');
    await close();

    // ── router and matrix: a patchbay, gains ────────────────────────────────
    at = await open(
      '.router',
      slug: 'router-matrix',
      notes: 6,
      heading: 'router passes messages from its data inlets',
    );
    await tapCell(0, 0);
    expect(await listShows('0 0 1.'), isTrue, reason: 'the cell, a decimal');
    await tap(message('10'));
    expect(await shown('.i', 60, 340), 10, reason: 'inlet 0 to outlet 0');
    expect(value(at('.i', 170, 340)), '0');
    await tapCell(0, 1);
    await tapCell(1, 1);
    await tap(message('20'));
    expect(await shown('.i', 170, 340), 20, reason: 'inlet 1 to outlet 1');
    await tap(message('10'));
    expect(value(at('.i', 170, 340)), '10', reason: 'inlet 0 to both');
    await tap(message('clear'));
    await tap(message('20'));
    expect(value(at('.i', 170, 340)), '10', reason: 'cleared');
    await typeInto('.f', 60, 440, '1');
    await typeInto('.f', 200, 440, '0.5');
    await tap(message('8'));
    expect(await shown('.f', 60, 610), 8, reason: 'gain 1');
    expect(await shown('.f', 170, 610), 4, reason: 'gain 0.5');
    await close();

    // ── split: a velocity split in three layers ─────────────────────────────
    at = await open(
      '.split',
      slug: 'split',
      notes: 4,
      heading: 'when it lies between its two',
    );
    await tap(message('63'));
    expect(await shown('.f', 60, 290), 63, reason: 'the limit is inside');
    await tap(message('64'));
    expect(await shown('.f', 200, 350), 64);
    await tap(message('110'));
    expect(await shown('.f', 340, 350), 110);
    await typeInto('.i', 500, 160, '-5');
    expect(await shown('.f', 340, 350), -5, reason: 'outside both');
    expect(read(at('.f', 60, 290)), 63);
    await close();

    // ── spray, funnel and cycle ─────────────────────────────────────────────
    at = await open(
      '.spray',
      slug: 'spray-funnel-cycle',
      notes: 5,
      heading: 'spray takes a list that starts with an outlet number',
    );
    await typeInto('.i', 60, 160, '1');
    expect(
      [
        for (final x in [60.0, 150.0, 240.0]) value(at('.i', x, 320)),
      ],
      ['0', '60', '64'],
    );
    await typeInto('.i', 60, 160, '-1');
    expect(await shown('.i', 60, 320), 60, reason: 'repeated across');
    expect(value(at('.i', 240, 320)), '60');
    await typeInto('.i', 150, 410, '6');
    expect(await listShows('1 6'), isTrue, reason: 'inlet 1, then 6');
    expect(await shown('.i', 150, 590), 6, reason: 'back out outlet 1');
    for (final m in ['60', '64', '67', '60']) {
      await tap(message(m));
    }
    expect(
      [
        for (final x in [60.0, 150.0, 240.0]) value(at('.i', x, 780)),
      ],
      ['60', '64', '67'],
      reason: 'round the outlets',
    );
    await close();

    // ── bucket and decode ───────────────────────────────────────────────────
    at = await open(
      '.bucket',
      slug: 'bucket-decode',
      notes: 5,
      heading: 'bucket is a bucket brigade',
    );
    for (final n in ['1', '2', '3']) {
      await typeInto('.i', 60, 160, n);
    }
    expect(
      [
        for (final x in [60.0, 150.0, 240.0, 340.0, 430.0, 520.0])
          value(at('.i', x, 280)),
      ],
      ['2', '1', '0', '3', '2', '1'],
      reason: 'one step behind, and echo',
    );
    await tap(buttonAt(170, 160));
    expect(await shown('.i', 60, 280), 3, reason: 'the bang shows the 3');
    await typeInto('.i', 60, 420, '2');
    List<String> bank() => [
      for (final x in [60.0, 110.0, 160.0, 210.0]) value(at('.t', x, 540)),
    ];
    expect(bank(), ['off', 'off', 'on', 'off']);
    await tap(toggleAt(200, 420));
    expect(bank(), ['on', 'on', 'on', 'on'], reason: 'all on');
    await tap(toggleAt(260, 420));
    expect(bank(), ['off', 'off', 'off', 'off'], reason: 'muted');
    await tap(toggleAt(260, 420));
    await tap(toggleAt(200, 420));
    expect(bank(), ['off', 'off', 'on', 'off'], reason: 'the selection');
    await close();

    expect(loudness(), 0, reason: 'nothing here makes a sound');
    expect(library.tutorial, isNull);
    expect(
      project.registry.childrenOfKind(RegistryKinds.patch).length,
      patchCount,
      reason: 'opening tutorials never touches the project',
    );

    await tester.pumpWidget(const SizedBox());
    await engine.dispose();
    await yse.dispose();
    project.dispose();
    appSettings.dispose();
    session.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}
