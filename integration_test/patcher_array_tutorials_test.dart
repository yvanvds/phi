import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_bang_square.dart';
import 'package:phi/design/widgets/patcher/patch_list_box.dart';
import 'package:phi/design/widgets/patcher/patch_message_box.dart';
import 'package:phi/design/widgets/patcher/patch_note_box.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
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

/// End-to-end proof of the **array tutorials** (issue #507) through the real
/// [PhiApp]: real rail navigation, fonts and layout, the real asset bundle and
/// the real patcher engine ([RealPatcherGateway] on an offline libyse
/// session). Only the audio device and MIDI are fakes.
///
/// The eight array tutorials (array; editing; cutting and combining; the
/// functional family; reordering; statistics; sets and comparisons;
/// converting) are opened from the palette's Tutorials tab by searching for a
/// type they cover. The test checks that the notes render, nothing overlaps
/// and every list box shows its list uncut, then plays each patch the way its
/// notes say with real taps and real typing into number boxes, and reads the
/// results back from the canvas. The arrays the tutorials start with ship in
/// the patch's saved state.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: every array tutorial opens from the Tutorials tab '
      'and does what its notes say', (tester) async {
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
          newLocationPath: '/projects/array-tutorials.phi',
        ),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(PatcherPalette.tabKey(PatcherPaletteTab.tutorials)),
    );
    await tester.pumpAndSettle();

    final library = engine.patchLibrary;

    // Renders [blocks] blocks of the offline session and returns the loudest
    // master peak among them.
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

    // Opens the tutorial of [type] from the browser and checks the banner,
    // the slug, the notes and that nothing overlaps.
    Future<void> open(
      String type, {
      required String slug,
      required int notes,
      required String heading,
    }) async {
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
      // Mounted while open (#528); libyse sets the sound up in wall-clock
      // time, so render with real pauses until it is in the mix (#525).
      final instance = tutorial.instanceId;
      for (var i = 0; i < 5000; i++) {
        if (gateway.isSourceReady(instance)) break;
        System.instance
          ..renderOffline(1)
          ..update();
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(gateway.isSourceReady(instance), isTrue, reason: slug);
      loudness(20);
    }

    Future<void> tap(Finder f) async {
      expect(f, findsOneWidget);
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    Future<void> close() async {
      expectListBoxesUncut(tester, where: library.tutorial?.slug ?? '');
      expect(loudness(), 0, reason: 'an array makes no sound');
      await tap(find.byKey(PatchTutorialBar.closeKey));
    }

    Finder nodeAt(String type, double x, double y) => find.byWidgetPredicate(
      (w) =>
          w is PatcherNodeView &&
          w.node.type == type &&
          w.node.position == Offset(x, y),
    );
    Finder buttonAt(double x, double y) => find.descendant(
      of: nodeAt('.b', x, y),
      matching: find.byType(PatchBangSquare),
    );
    Finder messageAt(double x, double y) => find.descendant(
      of: nodeAt('.m', x, y),
      matching: find.byType(PatchMessageBox),
    );
    Finder numberField(String type, double x, double y) => find.descendant(
      of: nodeAt(type, x, y),
      matching: find.descendant(
        of: find.byType(NumberNodeBody),
        matching: find.byType(TextField),
      ),
    );

    // Lets a few blocks run and the surface's live-value poll come due.
    Future<void> settle() async {
      loudness(5);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
    }

    // What the number box at ([x], [y]) shows on the canvas.
    Future<double> shown(String type, double x, double y) async {
      await settle();
      final field = numberField(type, x, y);
      expect(field, findsOneWidget, reason: '$type at ($x, $y)');
      return double.parse(tester.widget<TextField>(field).controller!.text);
    }

    // What the list box at ([x], [y]) shows on the canvas.
    Future<String> listAt(double x, double y) async {
      await settle();
      final text = find.descendant(
        of: nodeAt('.l', x, y),
        matching: find.descendant(
          of: find.byType(PatchListBox),
          matching: find.byType(Text),
        ),
      );
      expect(text, findsOneWidget, reason: '.l at ($x, $y)');
      return tester.widget<Text>(text).data ?? '';
    }

    // Types [text] into the number box at ([x], [y]) and commits it.
    Future<void> typeInto(String type, double x, double y, String text) async {
      final field = numberField(type, x, y);
      // Through the shared helper, which survives the window going
      // inactive mid-typing (#544).
      await typeIntoField(tester, field, text, what: '$type at ($x, $y)');
    }

    // array.deserialize parses on the engine's background pool and lands on a
    // later block: render with real pauses until [done] holds.
    Future<void> renderUntil(Future<bool> Function() done) async {
      for (var i = 0; i < 200; i++) {
        if (await done()) return;
        loudness(2);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      expect(await done(), isTrue, reason: 'the background work finished');
    }

    // ── array ───────────────────────────────────────────────────────────────
    await open(
      '.array.indexof',
      slug: 'array',
      notes: 6,
      heading: 'Positions start at 0',
    );
    await tap(messageAt(60, 220));
    expect(await listAt(60, 460), 'got 60 64 67 72');
    await tap(messageAt(170, 220));
    expect(await listAt(60, 460), 'got 4');
    await typeInto('.i', 280, 220, '2');
    expect(await listAt(60, 460), 'got 67');
    await typeInto('.i', 280, 220, '9');
    expect(await listAt(60, 460), 'missing');
    await typeInto('.i', 400, 220, '76');
    await tap(messageAt(60, 220));
    expect(await listAt(60, 460), 'got 60 64 67 72 76');
    expectListBoxesUncut(tester, where: 'array, the longest array');
    await tap(buttonAt(520, 220));
    expect(await listAt(300, 460), 'array notes');
    expect(await shown('.i', 480, 460), 5);
    await typeInto('.i', 60, 560, '1');
    expect(await listAt(60, 740), 'at 64');
    await typeInto('.i', 60, 560, '9');
    expect(await listAt(60, 740), 'miss');
    await typeInto('.i', 300, 560, '67');
    expect(await listAt(300, 740), 'index 2');
    expect(await shown('.i', 540, 680), 2);
    await typeInto('.i', 300, 560, '61');
    expect(await listAt(300, 740), 'none');
    expect(await shown('.i', 540, 680), -1);
    await tap(buttonAt(60, 820));
    expect(await listAt(300, 880), 'array notes');
    await tap(messageAt(60, 220));
    expect(await listAt(60, 460), 'got 72 67 64 60');
    await close();

    // ── editing ─────────────────────────────────────────────────────────────
    await open(
      '.array.unshift',
      slug: 'array-edit',
      notes: 5,
      heading: 'push with pop makes a stack',
    );
    await typeInto('.i', 60, 220, '66');
    expect(await listAt(60, 460), 'now 60 62 64 66');
    await typeInto('.i', 240, 220, '58');
    expect(await listAt(60, 460), 'now 58 60 62 64 66');
    expectListBoxesUncut(tester, where: 'array-edit, longest queue');
    await tap(buttonAt(420, 220));
    expect(await listAt(420, 400), 'took 66');
    expect(await listAt(60, 460), 'now 58 60 62 64');
    await tap(buttonAt(580, 220));
    expect(await listAt(420, 400), 'took 58');
    expect(await listAt(60, 460), 'now 60 62 64');
    await typeInto('.i', 180, 540, '1');
    await typeInto('.i', 60, 540, '61');
    expect(await listAt(60, 460), 'now 60 61 62 64');
    await typeInto('.i', 420, 540, '0');
    expect(await listAt(420, 400), 'took 60');
    expect(await listAt(60, 460), 'now 61 62 64');
    await typeInto('.i', 420, 540, '9');
    expect(await listAt(420, 400), 'miss');
    await tap(buttonAt(60, 680));
    expect(await shown('.i', 60, 800), 1);
    expect(await listAt(60, 460), 'now 61 62 99');
    await tap(buttonAt(60, 680));
    expect(await shown('.i', 60, 800), 0);
    await tap(buttonAt(420, 680));
    expect(await listAt(60, 460), 'now 0 0 0 0');
    for (var i = 0; i < 4; i++) {
      await tap(buttonAt(420, 220));
    }
    await tap(buttonAt(420, 220));
    expect(await listAt(420, 400), 'empty');
    expect(await listAt(60, 460), 'empty');
    await close();

    // ── cutting and combining ───────────────────────────────────────────────
    await open(
      '.array.flatten',
      slug: 'array-slice-combine',
      notes: 5,
      heading: 'Only array.thin changes its array',
    );
    await tap(buttonAt(60, 300));
    expect(await listAt(60, 480), 'slice 62 64 65');
    await tap(buttonAt(260, 300));
    expect(await listAt(260, 480), 'sub 67 65 64 62');
    await tap(buttonAt(480, 300));
    expect(await listAt(480, 480), 'head 60 62 64');
    expect(await listAt(480, 540), 'tail 65 67 69 71');
    for (final (pos, want) in [('7', 60), ('9', 64), ('-1', 71)]) {
      await typeInto('.i', 60, 620, pos);
      expect(await shown('.i', 60, 740), want, reason: 'wrap $pos');
    }
    await tap(buttonAt(220, 620));
    expect(await listAt(220, 740), '60 62 64 65 67 69 71 36 43');
    await tap(buttonAt(500, 620));
    expect(await listAt(500, 740), '36 43 c4 e4 g4 36 43');
    await tap(buttonAt(60, 800));
    expect(await listAt(60, 920), 'c4-e4-g4');
    await tap(buttonAt(220, 800));
    expect(await listAt(220, 980), '| 60 60 60 | 64 64 | 67');
    await tap(buttonAt(500, 800));
    expect(await shown('.i', 660, 920), 3);
    expect(await listAt(500, 980), '0 0.8 3');
    await close();

    // ── the functional family ───────────────────────────────────────────────
    await open(
      '.array.reduce',
      slug: 'array-functional',
      notes: 6,
      heading: 'callback outlet',
    );
    await tap(buttonAt(60, 220));
    expect(await listAt(300, 400), '72 76 79');
    expect(await listAt(420, 460), '0 4 7');
    expect(await listAt(400, 520), '0 4 7');
    expect(await shown('.i', 300, 580), 191);
    expect(await shown('.i', 300, 640), 1);
    expect(await shown('.i', 300, 700), 0);
    expect(await listAt(340, 760), '72 64 55');
    await tap(buttonAt(300, 220));
    expect(await listAt(300, 400), '79 83 86');
    expect(await listAt(420, 460), '7 11 2');
    expect(await listAt(400, 520), '7 11 14');
    expect(await shown('.i', 300, 580), 212);
    expect(await shown('.i', 300, 700), 1);
    expect(await listAt(340, 760), '79 71 62');
    await tap(buttonAt(560, 220));
    expect(await listAt(560, 400), '60 72 65');
    for (final (v, short) in [('1', 3), ('2', 2), ('3', 1)]) {
      await typeInto('.i', 580, 520, v);
      expect(await shown('.i', 740, 640), short);
    }
    expect(await listAt(580, 700), isNot(contains('3')), reason: 'not full');
    await typeInto('.i', 580, 520, '4');
    expect(await shown('.i', 740, 640), 0);
    expect(await listAt(580, 700), '1 2 3 4');
    await typeInto('.i', 580, 520, '5');
    expect(await listAt(580, 700), '2 3 4 5');
    await close();

    // ── reordering ──────────────────────────────────────────────────────────
    await open(
      '.array.scramble',
      slug: 'array-order-random',
      notes: 5,
      heading: 'each note keeps its',
    );
    const velOf = {64: 90, 60: 100, 67: 70, 62: 110, 65: 80};
    Future<void> expectPaired() async {
      final notes = (await listAt(60, 480)).split(' ').map(int.parse).toList();
      expect(notes.toSet(), velOf.keys.toSet(), reason: 'a reorder');
      expect(
        await listAt(300, 480),
        [for (final n in notes) velOf[n]].join(' '),
        reason: 'vel follows row',
      );
    }

    await tap(buttonAt(600, 220));
    await expectPaired();
    await tap(buttonAt(60, 220));
    expect(await listAt(60, 480), '60 62 64 65 67');
    expect(await listAt(300, 480), '100 110 90 80 70');
    await tap(messageAt(120, 220));
    expect(await listAt(60, 480), '67 65 64 62 60');
    expect(await listAt(560, 360), '4 3 2 1 0');
    await tap(buttonAt(60, 560));
    await expectPaired();
    await tap(buttonAt(60, 220));
    await tap(buttonAt(260, 220));
    expect(await listAt(60, 480), '67 65 64 62 60');
    await typeInto('.i', 420, 220, '1');
    expect(await listAt(60, 480), '60 67 65 64 62');
    await typeInto('.i', 420, 220, '-1');
    expect(await listAt(60, 480), '67 65 64 62 60');
    for (var i = 0; i < 5; i++) {
      await tap(buttonAt(300, 560));
      expect(velOf.keys, contains((await shown('.i', 300, 680)).toInt()));
    }
    expect(await listAt(60, 480), '67 65 64 62 60');
    await close();

    // ── statistics ──────────────────────────────────────────────────────────
    await open(
      '.array.stddev',
      slug: 'array-stats',
      notes: 4,
      heading: 'vel opens holding six velocities',
    );
    await tap(buttonAt(60, 220));
    expect(await shown('.i', 60, 460), 127);
    expect(await shown('.i', 220, 460), 40);
    expect(await shown('.i', 380, 460), 64);
    expect(await shown('.f', 60, 580), closeTo(80.83, 0.01));
    expect(await shown('.f', 220, 580), 77);
    expect(await shown('.f', 380, 580), closeTo(28.33, 0.01));
    await typeInto('.i', 200, 220, '127');
    expect(await shown('.i', 380, 460), 64, reason: 'a tie: the first');
    await typeInto('.i', 200, 220, '127');
    expect(await shown('.i', 380, 460), 127);
    expect(await shown('.f', 60, 580), closeTo(92.375, 0.01));
    await tap(messageAt(360, 220));
    await tap(buttonAt(60, 220));
    expect(await listAt(560, 640), 'empty');
    await close();

    // ── sets and comparisons ────────────────────────────────────────────────
    await open(
      '.array.routepass',
      slug: 'array-sets-compare',
      notes: 4,
      heading: 'array.compare also',
    );
    for (final (x, want) in [
      (60.0, '60 64'),
      (240.0, '60 64 67 57'),
      (440.0, '60 62 64'),
      (600.0, '64 60 62'),
    ]) {
      await tap(buttonAt(x, 220));
      expect(await listAt(x, 340), want, reason: 'at $x');
    }
    await tap(buttonAt(60, 480));
    expect(await shown('.i', 60, 680), 1);
    expect(await shown('.i', 280, 680), 1);
    expect(await listAt(600, 760), 'fifth');
    await tap(buttonAt(60, 480));
    expect(await shown('.i', 280, 680), 0);
    await typeInto('.i', 200, 480, '70');
    expect(await shown('.i', 60, 680), 0);
    expect(await shown('.i', 280, 680), 1);
    expect(await listAt(600, 760), 'seventh');
    await tap(messageAt(380, 480));
    await tap(buttonAt(60, 480));
    expect(await listAt(600, 760), 'neither');
    await close();

    // ── converting ──────────────────────────────────────────────────────────
    await open(
      '.array.deserialize',
      slug: 'array-convert',
      notes: 5,
      heading: 'only array.deserialize writes one',
    );
    await tap(buttonAt(60, 220));
    expect(await listAt(60, 400), 'kick 1 .wav');
    expect(await listAt(260, 400), 'kick 1 .wav');
    expect(await listAt(480, 400), 'kick1.wav');
    await tap(buttonAt(60, 480));
    expect(await shown('.i', 60, 660), 7);
    expect(await listAt(240, 660), '7');
    await tap(messageAt(440, 480));
    await renderUntil(() async => await listAt(440, 660) == '60 62.5 kick');
    await tap(messageAt(620, 480));
    loudness(20);
    expect(await listAt(440, 660), '60 62.5 kick');
    await tap(buttonAt(60, 740));
    expect(await listAt(60, 860), 'c4 c5');
    await tap(buttonAt(300, 740));
    expect(await listAt(300, 860), 'e4 snare');
    await close();

    await tester.pumpWidget(const SizedBox());
    await engine.dispose();
    await yse.dispose();
  });
}
