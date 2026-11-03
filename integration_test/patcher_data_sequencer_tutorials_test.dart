import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_bang_square.dart';
import 'package:phi/design/widgets/patcher/patch_keyboard.dart';
import 'package:phi/design/widgets/patcher/patch_list_box.dart';
import 'package:phi/design/widgets/patcher/patch_message_box.dart';
import 'package:phi/design/widgets/patcher/patch_note_box.dart';
import 'package:phi/design/widgets/patcher/patch_toggle_square.dart';
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
import '../test/surfaces/patcher/test_support/engine_file_dir.dart';
import '../test/surfaces/patcher/test_support/expect_list_boxes_uncut.dart';
import '../test/surfaces/patcher/test_support/open_tutorial_by_search.dart';
import '../test/surfaces/patcher/test_support/type_into_field.dart';

/// End-to-end proof of the **data store and sequencer tutorials** (issue
/// #505) through the real [PhiApp]: real rail navigation, fonts and layout,
/// the real asset bundle and the real patcher engine ([RealPatcherGateway] on
/// an offline libyse session). Only the audio device and MIDI are fakes.
///
/// The coll, table, funbuff, bag, capture, textfile, seq, qlist and mtr
/// tutorials are opened from the palette's Tutorials tab by searching for
/// their type. The test checks that the notes render and nothing overlaps,
/// then plays each patch the way its notes say, with real taps, real typing
/// into number boxes and real key presses on a keyboard, and reads the
/// results back from the canvas. The sequencers count time in audio blocks,
/// so the test renders a known number of blocks between events and the
/// rhythms it checks do not depend on wall-clock time. The coll and textfile
/// file round trips write where libYSE resolves a relative name
/// ([engineFileDir]: a temporary working directory on Linux, the executable's
/// folder on Windows, #541).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: every data store and sequencer tutorial opens from '
      'the Tutorials tab and does what its notes say', (tester) async {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
    addTearDown(System.instance.close);

    // A relative file name lands where libYSE resolves it: the working
    // directory on Linux, so switch it to a fresh one, and the executable's
    // folder on Windows (#541, yse-soundengine#1249). Clear the tutorials'
    // files there first, so a file found proves this run wrote it.
    final workDir = Directory.systemTemp.createTempSync('phi_505_it_');
    final oldDir = Directory.current;
    Directory.current = workDir;
    final fileDir = engineFileDir();
    File engineFile(String name) =>
        File('${fileDir.path}${Platform.pathSeparator}$name');
    void removeTutorialFiles() {
      for (final name in ['cues.txt', 'lines.txt']) {
        final f = engineFile(name);
        if (f.existsSync()) f.deleteSync();
      }
    }

    removeTutorialFiles();
    addTearDown(() {
      removeTutorialFiles();
      Directory.current = oldDir;
      workDir.deleteSync(recursive: true);
    });

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
          newLocationPath: '/projects/data-tutorials.phi',
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

    late int instance;

    // Opens [type]'s tutorial from the browser and checks the banner, the
    // slug, the notes and that nothing overlaps.
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
      instance = tutorial.instanceId;
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
    Finder toggleAt(double x, double y) => find.descendant(
      of: nodeAt('.t', x, y),
      matching: find.byType(PatchToggleSquare),
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

    // The engine's value of the object [type] at ([x], [y]), read at once
    // without rendering: for the block-by-block rhythm checks.
    int handle(String type, double x, double y) => gateway
        .enumerate(instance)
        .objects
        .firstWhere((o) => o.type == type && o.position == Offset(x, y))
        .handleId;
    String value(int id) => gateway.guiValue(instance, id);

    // The blocks at which [read] changed, and what it changed to, over
    // [blocks] rendered blocks.
    List<(int, String)> watch(String Function() read, int blocks) {
      final seen = <(int, String)>[];
      var last = read();
      for (var b = 0; b < blocks; b++) {
        loudness(1);
        final now = read();
        if (now != last) seen.add((b, now));
        last = now;
      }
      return seen;
    }

    // A file request finishes on a worker thread and is delivered on a later
    // block: render with real pauses until [done] holds. [seen] describes the
    // state for the failure message.
    Future<void> renderUntil(
      bool Function() done, {
      required String Function() seen,
    }) async {
      for (var i = 0; i < 500 && !done(); i++) {
        loudness(2);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
      }
      expect(done(), isTrue, reason: 'the file request finished: ${seen()}');
    }

    // ── coll ────────────────────────────────────────────────────────────────
    await open(
      '.coll',
      slug: 'coll',
      notes: 5,
      heading: 'A coll stores messages, each at an address',
    );
    await typeInto('.i', 60, 200, '2');
    expect(await listAt(60, 320), '62 65 69');
    await tap(messageAt(140, 200));
    expect(await listAt(60, 320), '0 0 0', reason: 'the word address intro');
    await tap(messageAt(250, 200));
    expect(await listAt(250, 380), 'address 1');
    expect(await listAt(60, 320), '60 64 67');
    await tap(messageAt(250, 200));
    expect(await listAt(250, 380), 'address 2');
    await tap(messageAt(360, 200));
    expect(await listAt(60, 320), '0 0 0', reason: 'dump ends with intro');
    await typeInto('.i', 60, 460, '79');
    await typeInto('.i', 60, 200, '4');
    expect(await listAt(60, 320), '72 76 79', reason: 'one shared collection');
    await tap(messageAt(60, 660));
    final cues = engineFile('cues.txt');
    await renderUntil(cues.existsSync, seen: () => whereIs('cues.txt'));
    expect(cues.readAsStringSync(), contains('4, 72 76 79;'));
    await tap(messageAt(200, 660));
    await typeInto('.i', 60, 200, '2');
    expect(await listAt(60, 320), '72 76 79', reason: 'cleared: nothing sent');
    await tap(messageAt(300, 660));
    // The read lands on a later block: recall 2 until the entry is back.
    final topColl = handle('.coll', 60, 260);
    final data = handle('.l', 60, 320);
    await renderUntil(() {
      gateway.sendInt(instance, topColl, 0, 2);
      return value(data) == '62 65 69';
    }, seen: () => 'recall 2 sends "${value(data)}"; ${whereIs('cues.txt')}');
    await typeInto('.i', 60, 200, '3');
    expect(await listAt(60, 320), '64 67 71', reason: 'read from cues.txt');
    await close();

    // ── table ───────────────────────────────────────────────────────────────
    await open(
      '.table',
      slug: 'table',
      notes: 4,
      heading: 'A table holds ints at the addresses',
    );
    const steps = [60, 62, 64, 65, 67, 69, 71, 72];
    await tap(toggleAt(60, 200));
    await tap(toggleAt(60, 200));
    final step = (await shown('.i', 60, 400)).toInt();
    expect(step, inInclusiveRange(0, 7));
    expect(await shown('.i', 60, 520), steps[step], reason: 'the metro step');
    await typeInto('.i', 60, 400, '3');
    expect(await shown('.i', 60, 520), 65);
    await typeInto('.i', 200, 400, '72');
    await typeInto('.i', 60, 400, '3');
    expect(await shown('.i', 60, 520), 65, reason: 'stored, nothing sent');
    await typeInto('.i', 60, 400, '3');
    expect(await shown('.i', 60, 520), 72);
    final picks = <int>{};
    for (var i = 0; i < 40; i++) {
      await tester.tap(buttonAt(60, 620));
      await tester.pump();
      picks.add(int.parse(value(handle('.i', 60, 730))));
    }
    expect(picks.difference({0, 1, 3}), isEmpty, reason: 'weight 0: never 2');
    expect(picks, contains(3));
    await close();

    // ── funbuff ─────────────────────────────────────────────────────────────
    await open(
      '.funbuff',
      slug: 'funbuff',
      notes: 5,
      heading: 'A funbuff stores (x, y) pairs of ints',
    );
    await typeInto('.i', 60, 220, '150');
    expect(await shown('.f', 60, 400), 50);
    await typeInto('.f', 260, 220, '200');
    expect(await shown('.f', 60, 400), 35);
    await typeInto('.i', 160, 220, '99');
    await typeInto('.i', 60, 220, '200');
    expect(await shown('.f', 60, 400), 35, reason: 'stored, nothing sent');
    await typeInto('.i', 60, 220, '250');
    expect(await shown('.f', 60, 400), 99);
    final walked = <(double, double)>[];
    for (var i = 0; i < 4; i++) {
      await tap(messageAt(360, 220));
      walked.add((await shown('.i', 180, 400), await shown('.f', 60, 400)));
    }
    expect(walked, [(0, 10), (100, 50), (100, 99), (100, 20)]);
    await tap(messageAt(470, 220));
    await tap(messageAt(360, 220));
    expect(await shown('.f', 60, 400), 10, reason: 'goto 0, back to start');
    await close();

    // ── bag ─────────────────────────────────────────────────────────────────
    await open(
      '.bag',
      slug: 'bag',
      notes: 4,
      heading: 'A bag holds a set of numbers',
    );
    await tap(toggleAt(60, 200));
    await tap(toggleAt(160, 200));
    await tap(buttonAt(380, 200));
    expect(await listAt(380, 400), 'held 64 60');
    await tap(toggleAt(60, 200));
    await tap(buttonAt(380, 200));
    expect(await listAt(380, 400), 'held 64');
    await tap(messageAt(480, 200));
    await tap(buttonAt(380, 200));
    expect(await listAt(380, 400), 'held');
    await close();

    // ── capture ─────────────────────────────────────────────────────────────
    await open(
      '.capture',
      slug: 'capture',
      notes: 4,
      heading: 'A capture records every value that reaches it',
    );
    for (var i = 0; i < 6; i++) {
      await tap(buttonAt(60, 200));
    }
    expect(await shown('.i', 60, 320), 6);
    await tap(buttonAt(240, 200));
    expect(await listAt(300, 500), 'past 3 4 5 6');
    await tap(messageAt(400, 200));
    expect(await shown('.i', 160, 440), 6);
    await tap(messageAt(400, 200));
    expect(await shown('.i', 160, 440), 0);
    await tap(messageAt(510, 200));
    await tap(buttonAt(240, 200));
    expect(await listAt(300, 500), 'past');
    await close();

    // ── textfile ────────────────────────────────────────────────────────────
    await open(
      '.textfile',
      slug: 'textfile',
      notes: 4,
      heading: 'A textfile collects messages as lines of text',
    );
    for (final n in ['60', '64', '67']) {
      await typeInto('.i', 60, 200, n);
    }
    await tap(messageAt(235, 200));
    await tap(messageAt(135, 200));
    await tap(messageAt(235, 200));
    await tap(messageAt(335, 200));
    expect(await shown('.i', 200, 510), 2);
    await typeInto('.i', 440, 200, '1');
    expect(await listAt(60, 570), '60 64 67');
    await typeInto('.i', 440, 200, '2');
    expect(await listAt(60, 570), 'intro');
    await tap(messageAt(200, 270));
    final lines = engineFile('lines.txt');
    await renderUntil(lines.existsSync, seen: () => whereIs('lines.txt'));
    expect(lines.readAsLinesSync(), ['60 64 67', 'intro']);
    await tap(messageAt(320, 270));
    await tap(messageAt(335, 200));
    expect(await shown('.i', 200, 510), 0, reason: 'cleared');
    await tap(messageAt(330, 330));
    final textfile = handle('.textfile', 60, 450);
    final count = handle('.i', 200, 510);
    await renderUntil(() {
      gateway.sendMessage(instance, textfile, 0, 'query');
      return value(count) == '2';
    }, seen: () => 'query says ${value(count)}; ${whereIs('lines.txt')}');
    await typeInto('.i', 440, 200, '1');
    expect(await listAt(60, 570), '60 64 67', reason: 'read back');
    await close();

    // ── seq ─────────────────────────────────────────────────────────────────
    await open(
      '.seq',
      slug: 'seq',
      notes: 5,
      heading: 'A seq records raw MIDI bytes',
    );
    final keyboards = find.byType(PatchKeyboard);
    expect(keyboards, findsNWidgets(2));
    // The keyboard of the .kslider at (60, [y]).
    Finder keyboardAt(double y) => find.descendant(
      of: nodeAt('.kslider', 60, y),
      matching: find.byType(PatchKeyboard),
    );
    Finder upper() => keyboardAt(200);
    Offset keyAt(Finder board, int pitch) {
      final box = tester.getRect(board);
      final b = tester.widget<PatchKeyboard>(board).layout.boundsOf(pitch);
      return box.topLeft +
          Offset(box.width * (b.left + b.right) / 2, box.height * 0.85);
    }

    // Holds a key down for [blocks] blocks of audio, then lets go.
    Future<void> hold(int pitch, int blocks) async {
      final pointer = await tester.startGesture(keyAt(upper(), pitch));
      await tester.pump();
      loudness(blocks);
      await pointer.up();
      await tester.pump();
    }

    await tap(messageAt(340, 200));
    loudness(10);
    await hold(60, 20);
    loudness(20);
    await hold(64, 20);
    await tap(messageAt(440, 200));
    final note = handle('.l', 360, 570);
    // A note as pitch and on or off: the velocity is how low the key was
    // pressed.
    String noteOf(String list) {
      final parts = list.split(' ');
      if (parts.length != 2) return list;
      return '${parts[0]} ${parts[1] == '0' ? 'off' : 'on'}';
    }

    await tap(messageAt(540, 200));
    final asRecorded = watch(() => noteOf(value(note)), 150);
    expect(asRecorded.map((e) => e.$2), ['60 on', '60 off', '64 on', '64 off']);
    expect(asRecorded[1].$1 - asRecorded[0].$1, inInclusiveRange(18, 22));
    expect(asRecorded[2].$1 - asRecorded[0].$1, inInclusiveRange(38, 42));
    expect(await listAt(360, 570), '64 0');
    // Note 3: -1 on seqclock at 120 BPM plays about as recorded.
    await tap(messageAt(360, 330));
    final onClock = watch(() => noteOf(value(note)), 200);
    expect(onClock.map((e) => e.$2), ['60 on', '60 off', '64 on', '64 off']);
    expect(onClock[2].$1 - onClock[0].$1, inInclusiveRange(32, 48));
    // Note 4: at 60 BPM, half speed.
    await tap(messageAt(60, 670));
    await tap(messageAt(360, 330));
    final slow = watch(() => noteOf(value(note)), 300);
    expect(slow[2].$1 - slow[0].$1, inInclusiveRange(72, 88));
    await tap(messageAt(170, 670));
    // Played back, the lower keyboard lights the key while it is held.
    await tap(messageAt(540, 200));
    watch(() => noteOf(value(note)), 15);
    expect(noteOf(value(note)), '60 on');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(tester.widget<PatchKeyboard>(keyboardAt(570)).held.keys, [
      60,
    ], reason: 'the playback lights its key');
    loudness(100);
    expect(loudness(), 0, reason: 'nothing here makes a sound');
    await close();

    // ── qlist ───────────────────────────────────────────────────────────────
    await open(
      '.qlist',
      slug: 'qlist',
      notes: 4,
      heading: 'A qlist is a list of lines played in time',
    );
    final pitch = handle('.i', 60, 540);
    await tap(buttonAt(60, 220));
    final score = watch(() => value(pitch), 450);
    expect(score.map((e) => e.$2), ['60', '64', '67']);
    expect(score[1].$1 - score[0].$1, inInclusiveRange(180, 195));
    expect(await shown('.i', 60, 540), 67);
    expect(await shown('.f', 200, 540), closeTo(0.2, 1e-6));
    expect(await shown('.i', 60, 400), 500, reason: 'the waits');
    await tap(messageAt(320, 220));
    await tap(messageAt(110, 220));
    expect(await shown('.i', 60, 540), 60, reason: 'next, by hand');
    expect(await shown('.f', 200, 540), 0.5);
    await tap(messageAt(110, 220));
    expect(await shown('.i', 60, 540), 64);
    await typeInto('.f', 430, 220, '2');
    await tap(buttonAt(60, 220));
    final fast = watch(() => value(pitch), 300);
    expect(fast.map((e) => e.$2), ['60', '64', '67']);
    expect(fast[1].$1 - fast[0].$1, inInclusiveRange(89, 98));
    await close();

    // ── mtr ─────────────────────────────────────────────────────────────────
    await open(
      '.mtr',
      slug: 'mtr',
      notes: 4,
      heading: 'An mtr records the messages on each of its tracks',
    );
    final out1 = handle('.i', 60, 400);
    final out2 = handle('.i', 160, 400);
    String both() => '${value(out1)} ${value(out2)}';
    await tap(messageAt(60, 220));
    loudness(10);
    await typeInto('.i', 300, 280, '1');
    await typeInto('.i', 420, 280, '10');
    loudness(50);
    await typeInto('.i', 300, 280, '2');
    loudness(50);
    await typeInto('.i', 300, 280, '3');
    await typeInto('.i', 420, 280, '30');
    await tap(messageAt(270, 220));
    expect(both(), '0 0', reason: 'recording sends nothing');
    await tap(messageAt(165, 220));
    final replay = watch(both, 150);
    expect(replay.map((e) => e.$2), ['1 10', '2 10', '3 30']);
    expect(replay[1].$1 - replay[0].$1, 50, reason: 'the recorded rhythm');
    expect(await shown('.i', 60, 400), 3);
    expect(await shown('.i', 160, 400), 30);
    // Note 3: play into track 2 plays it alone.
    await typeInto('.i', 60, 400, '0');
    await typeInto('.i', 160, 400, '0');
    await tap(messageAt(420, 220));
    final alone = watch(both, 150);
    expect(alone.map((e) => e.$2), ['0 10', '0 30']);
    expect(await shown('.i', 60, 400), 0, reason: 'track 1 stays silent');
    await close();

    await tester.pumpWidget(const SizedBox());
    await engine.dispose();
    await yse.dispose();
  });
}
