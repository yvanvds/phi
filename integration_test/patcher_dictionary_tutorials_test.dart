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
import 'package:phi/engine/bridge/real_engine_log_source.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/diagnostics/log_panel.dart';
import 'package:phi/shell/diagnostics/log_panel_toggle.dart';
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

/// End-to-end proof of the **dictionary tutorials** (issue #506) through the
/// real [PhiApp]: real rail navigation, fonts and layout, the real asset
/// bundle, the real patcher engine ([RealPatcherGateway] on an offline libyse
/// session) and the real engine log feeding the log panel. Only the audio
/// device and MIDI are fakes.
///
/// The dict, dict.pack/unpack, dict.route/compare, dict.iter/slice/strip,
/// dict.join/group and dict.serialize/deserialize/print tutorials are opened
/// from the palette's Tutorials tab by searching for a type they cover. The
/// test checks that the notes render, nothing overlaps and every list box
/// shows its list uncut, then plays each patch the way its notes say with
/// real taps and real typing into number boxes, and reads the results back
/// from the canvas and the log panel. The dictionaries the tutorials start
/// with ship in the patch's saved state.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: every dictionary tutorial opens from the Tutorials '
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
      // dict.print writes to the engine log, which the log panel shows.
      engineLogSource: const RealEngineLogSource(),
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
          newLocationPath: '/projects/dictionary-tutorials.phi',
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
      expect(loudness(), 0, reason: 'a dictionary makes no sound');
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
      expect(field, findsOneWidget, reason: '$type at ($x, $y)');
      await tester.tap(field);
      await tester.pumpAndSettle();
      tester.binding.focusedEditable = null;
      await tester.enterText(field, text);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    // dict.deserialize parses on a worker thread and lands on a later block:
    // render with real pauses until [done] holds.
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

    // ── dict ────────────────────────────────────────────────────────────────
    await open(
      '.dict',
      slug: 'dict',
      notes: 6,
      heading: 'A dict holds entries: a key and a value',
    );
    await tap(messageAt(60, 220));
    expect(await listAt(60, 520), 'got 440');
    await tap(messageAt(170, 220));
    expect(await listAt(60, 520), 'got 0 4 7');
    await tap(messageAt(280, 220));
    expect(await listAt(60, 520), 'missing');
    await typeInto('.i', 400, 220, '330');
    await tap(messageAt(60, 220));
    expect(await listAt(60, 520), 'got 330');
    await tap(messageAt(200, 340));
    expect(await listAt(60, 520), 'got 3');
    await tap(messageAt(310, 340));
    expect(await listAt(60, 520), 'got chord freq gain');
    await tap(messageAt(530, 220));
    await tap(messageAt(170, 220));
    expect(await listAt(60, 520), 'missing', reason: 'chord was deleted');
    await tap(buttonAt(530, 340));
    expect(await listAt(320, 520), 'dictionary synth');
    await tap(messageAt(60, 600));
    expect(await shown('.i', 60, 780), 330, reason: 'one shared dictionary');
    await tap(messageAt(420, 340));
    await tap(messageAt(200, 340));
    expect(await listAt(60, 520), 'got 0', reason: 'cleared');
    await close();

    // ── dict.pack / dict.unpack ─────────────────────────────────────────────
    await open(
      '.dict.unpack',
      slug: 'dict-pack-unpack',
      notes: 4,
      heading: 'dict.unpack voice freq gain is its pair',
    );
    await typeInto('.f', 240, 220, '0.5');
    expect(
      await listAt(300, 340),
      isNot('dictionary voice'),
      reason: 'the right inlet only stores',
    );
    await typeInto('.i', 60, 220, '440');
    expect(await listAt(300, 340), 'dictionary voice');
    expect(await shown('.i', 60, 460), 440);
    expect(await shown('.f', 240, 460), 0.5);
    expect(await listAt(60, 580), '440 0.5');
    await typeInto('.f', 240, 220, '0.8');
    await typeInto('.i', 60, 220, '220');
    expect(await listAt(60, 580), '220 0.8');
    await close();

    // ── dict.route / dict.compare ───────────────────────────────────────────
    await open(
      '.dict.route',
      slug: 'dict-route-compare',
      notes: 4,
      heading: 'dict.compare mine theirs sends 1',
    );
    await typeInto('.i', 60, 220, '60');
    await tap(buttonAt(180, 340));
    expect(await listAt(60, 580), 'note');
    await tap(messageAt(60, 340));
    await typeInto('.i', 220, 220, '7');
    await tap(buttonAt(180, 340));
    expect(await listAt(60, 580), 'cc');
    await tap(messageAt(60, 340));
    await tap(buttonAt(180, 340));
    expect(await listAt(60, 580), 'none');
    await typeInto('.i', 220, 220, '7');
    await typeInto('.i', 60, 220, '60');
    await tap(buttonAt(180, 340));
    expect(await listAt(60, 580), 'note', reason: 'the first key wins');
    await tap(buttonAt(540, 280));
    expect(await shown('.i', 380, 460), 0);
    expect(await listAt(470, 460), 'tempo');
    await typeInto('.i', 380, 220, '100');
    await tap(buttonAt(540, 280));
    expect(await shown('.i', 380, 460), 1);
    expect(await listAt(470, 460), 'tempo', reason: 'nothing more is sent');
    await close();

    // ── dict.iter / dict.slice / dict.strip ─────────────────────────────────
    await open(
      '.dict.slice',
      slug: 'dict-iter-slice-strip',
      notes: 4,
      heading: 'synth holds name lead and two voices',
    );
    await tap(buttonAt(60, 220));
    expect(
      await listAt(60, 460),
      'name lead voice::1::freq 440 voice::1::gain 0.5 voice::2::freq 220',
    );
    await tap(buttonAt(60, 540));
    expect(await listAt(60, 720), '{"freq":440,"gain":0.5}');
    expect(
      await listAt(300, 720),
      '{"name":"lead","voice":{"2":{"freq":220}}}',
    );
    // Check the widest results before the strip shortens them.
    expectListBoxesUncut(tester, where: 'dict-iter-slice-strip');
    await tap(buttonAt(300, 220));
    expect(
      await listAt(60, 460),
      'name lead voice::1::freq 440 voice::1::gain 0.5',
    );
    await tap(buttonAt(60, 540));
    expect(await listAt(300, 720), '{"name":"lead"}');
    await close();

    // ── dict.join / dict.group ──────────────────────────────────────────────
    await open(
      '.dict.group',
      slug: 'dict-join-group',
      notes: 4,
      heading: 'where both hold a key, the preset value wins',
    );
    await tap(buttonAt(60, 220));
    expect(
      await listAt(60, 520),
      '{"freq":440,"gain":0.8,"wave":"sine","cutoff":1200}',
    );
    await typeInto('.f', 240, 220, '0.3');
    await tap(buttonAt(60, 220));
    expect(
      await listAt(60, 520),
      '{"freq":440,"gain":0.3,"wave":"sine","cutoff":1200}',
    );
    await tap(buttonAt(60, 600));
    expect(
      await listAt(60, 780),
      '{"synth":{"bass":"synth","lead":"synth"},'
      '"drums":{"kick":"drums","snare":"drums"}}',
    );
    await close();

    // ── dict.serialize / dict.deserialize / dict.print ──────────────────────
    await open(
      '.dict.print',
      slug: 'dict-serialize',
      notes: 4,
      heading: 'dict.print writes a dictionary to the log',
    );
    Finder logRow(String text) => find.descendant(
      of: find.byType(LogPanel),
      matching: find.textContaining(text),
    );
    await tap(find.byKey(LogPanelToggle.toggleKey));
    expect(find.byType(LogPanel), findsOneWidget, reason: 'the log toggle');
    await tap(buttonAt(60, 220));
    expect(
      await listAt(60, 400),
      '{"bpm":120,"chord":[0,4,7],"title":"intro"}',
    );
    await renderUntil(() async => await shown('.i', 60, 640) == 120);
    await renderUntil(
      () async => logRow('"title": "intro"').evaluate().isNotEmpty,
    );
    expect(logRow('copy: {'), findsWidgets);
    await tap(messageAt(260, 460));
    await renderUntil(() async => await shown('.i', 60, 640) == 90);
    await renderUntil(
      () async => logRow('"title": "outro"').evaluate().isNotEmpty,
    );
    await tap(find.byKey(LogPanelToggle.toggleKey));
    expect(find.byType(LogPanel), findsNothing);
    await close();

    await tester.pumpWidget(const SizedBox());
    await engine.dispose();
    await yse.dispose();
  });
}
