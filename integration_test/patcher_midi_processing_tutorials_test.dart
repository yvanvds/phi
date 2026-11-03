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
import 'package:phi/domain/log/log_level.dart' as phi;
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
import 'package:phi/shell/diagnostics/notice_center.dart';
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
import '../test/engine/test_support/midi_driver_unavailable.dart';
import '../test/engine/test_support/midi_loopback.dart';
import '../test/surfaces/patcher/test_support/expect_list_boxes_uncut.dart';
import '../test/surfaces/patcher/test_support/open_tutorial_by_search.dart';

/// End-to-end proof of the **MIDI processing tutorials** (issue #510) through
/// the real [PhiApp]: real rail navigation, fonts and layout, the real asset
/// bundle, the real patcher engine ([RealPatcherGateway] on an offline libyse
/// session) and the real engine log feeding the log panel. Only the audio
/// device and the app's own MIDI gateway are fakes.
///
/// The seven tutorials (makenote, stripnote, poly, sustain, borax, offer and
/// the MPE three) are opened from the palette's Tutorials tab by searching
/// for a type they cover. The test checks that the notes render, nothing
/// overlaps and every list box shows its list uncut, and plays each one with
/// real taps and key presses, reading the canvas, the log panel and the
/// master bus.
///
/// The MPE tutorial sends through `.midiout 0` and reads input port 0 with
/// `.midiin 0`. Where both port 0s are ALSA's `Midi Through`
/// ([MidiLoopback]), the canvas shows what mpeparse read back; elsewhere
/// (Windows, CI runners) the test checks what the patch builds.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: every MIDI processing tutorial opens from the '
      'Tutorials tab and does what its notes say', (tester) async {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
    addTearDown(System.instance.close);

    // The MPE tutorial sends on output port 0 and listens on input port 0:
    // the loopback must be both.
    final opened = MidiLoopback.open();
    final loop =
        opened != null && opened.inputPort == 0 && opened.outputPort == 0
        ? opened
        : null;
    addTearDown(() => opened?.close());
    if (loop == null) {
      // ignore: avoid_print
      print('no MIDI loopback on port 0: the steps that read it are skipped');
    }

    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final yse = FakeYseGateway();
    final gateway = RealPatcherGateway();
    final engine = PhiEngine(
      yse,
      patcherGateway: gateway,
      midiGateway: FakeMidiGateway(),
      // print writes to the engine log.
      engineLogSource: const RealEngineLogSource(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final notices = NoticeCenter.build();
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
        noticeCenter: notices,
        projectController: project,
        directoryPicker: FakeProjectDirectoryPicker(
          newLocationPath: '/projects/midi-processing-tutorials.phi',
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
    double loudness([int blocks = 60]) {
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

    // Silence on master: a saw at velocity 1 is still louder than this.
    const silent = 1e-4;
    const sounding = 0.01;

    // Renders with real pauses: a .midiout opens its port on a background
    // thread, and a message reaches the wire, and the patch, in wall-clock
    // time.
    Future<void> pause([int steps = 20]) async {
      for (var i = 0; i < steps; i++) {
        loudness(1);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 3)),
        );
      }
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
        loudness(1);
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(gateway.isSourceReady(instance), isTrue, reason: slug);
      await pause(40);
    }

    Future<void> tap(Finder f) async {
      expect(f, findsOneWidget);
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    // A closed tutorial's patch is destroyed by libyse a moment later, in
    // wall-clock time.
    Future<void> close() async {
      expectListBoxesUncut(tester, where: library.tutorial?.slug ?? '');
      await tap(find.byKey(PatchTutorialBar.closeKey));
      await pause(100);
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
    // A message box by its text: each tutorial's are unique.
    Future<void> click(String text) async => tap(
      find.descendant(
        of: find.byType(PatchMessageBox),
        matching: find.text(text),
      ),
    );
    Future<void> clicks(List<String> texts) async {
      for (final t in texts) {
        await click(t);
      }
    }

    // Lets a few blocks run and the surface's live-value poll come due.
    Future<void> settle() async {
      loudness(5);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
    }

    // What the number box at ([x], [y]) shows on the canvas.
    Future<double> shown(double x, double y, {String type = '.i'}) async {
      await settle();
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

    // The middle of [pitch]'s key on the keyboard of the .kslider at ([x],
    // [y]), low on the key, where it plays loud.
    Offset keyAt(double x, double y, int pitch) {
      final board = find.descendant(
        of: nodeAt('.kslider', x, y),
        matching: find.byType(PatchKeyboard),
      );
      final box = tester.getRect(board);
      final b = tester.widget<PatchKeyboard>(board).layout.boundsOf(pitch);
      return box.topLeft +
          Offset(box.width * (b.left + b.right) / 2, box.height * 0.85);
    }

    // Presses [pitch] on the keyboard at ([x], [y]), holds it for [blocks]
    // blocks of audio and [hold] of wall-clock time, and lets go. Returns the
    // loudest master peak while it was down.
    Future<double> play(
      double x,
      double y,
      int pitch, {
      int blocks = 20,
      Duration hold = Duration.zero,
    }) async {
      final pointer = await tester.startGesture(keyAt(x, y, pitch));
      await tester.pump();
      final peak = loudness(blocks);
      if (hold > Duration.zero) {
        await tester.runAsync(() => Future<void>.delayed(hold));
      }
      await pointer.up();
      await tester.pump();
      return peak;
    }

    // The log panel, open and cleared.
    Future<void> openLog() async {
      await tap(find.byKey(LogPanelToggle.toggleKey));
      expect(find.byType(LogPanel), findsOneWidget, reason: 'the log toggle');
      if (find.byKey(LogPanel.clearKey).evaluate().isNotEmpty) {
        await tap(find.byKey(LogPanel.clearKey));
      }
    }

    Future<void> closeLog() async {
      await tap(find.byKey(LogPanelToggle.toggleKey));
      expect(find.byType(LogPanel), findsNothing);
    }

    Finder logRow(String text) => find.descendant(
      of: find.byType(LogPanel),
      matching: find.textContaining(text),
    );
    // Waits for each of [rows] to show in the log panel.
    Future<void> logged(List<String> rows) async {
      for (final row in rows) {
        for (var i = 0; i < 100 && logRow(row).evaluate().isEmpty; i++) {
          await pause(2);
          await tester.pumpAndSettle();
        }
        expect(logRow(row), findsWidgets, reason: row);
      }
    }

    // ── makenote ────────────────────────────────────────────────────────────
    await open(
      '.makenote',
      slug: 'makenote',
      notes: 4,
      heading: 'makenote turns a pitch into a complete note',
    );
    expect(loudness(), lessThan(silent), reason: 'quiet until played');
    // Note 1: the metro's first bang plays at once.
    await tap(toggleAt(60, 250));
    const scale = [60.0, 62.0, 64.0, 66.0, 68.0, 70.0, 72.0];
    expect(scale, contains(await shown(60, 680)));
    expect(loudness(200), greaterThan(sounding), reason: 'a saw on master');
    await tap(toggleAt(60, 250));
    loudness(200);
    expect(await shown(170, 680), 0, reason: 'each note is released');
    expect(loudness(), lessThan(silent));
    // Note 2: the duration inlet sends nothing.
    await clicks(['50', '40']);
    expect(await shown(170, 680), 0);
    // Note 3.
    await clicks(['2000', '67']);
    expect((await shown(60, 680), await shown(170, 680)), (67, 40));
    expect(loudness(300), greaterThan(sounding), reason: 'two seconds long');
    await click('stop');
    expect(await shown(170, 680), 0, reason: 'stop releases it');
    expect(loudness(), lessThan(silent));
    await clicks(['110', '67', 'clear']);
    loudness(800);
    expect(await shown(170, 680), 110, reason: 'clear forgot the release');
    expect(loudness(), greaterThan(sounding));
    await clicks(['50', '67']);
    loudness(30);
    expect(await shown(170, 680), 0, reason: "another note's release");
    expect(loudness(), lessThan(silent));
    await close();

    // ── stripnote ───────────────────────────────────────────────────────────
    await open(
      '.stripnote',
      slug: 'stripnote',
      notes: 4,
      heading: 'stripnote passes a note only when its velocity is not 0',
    );
    expect(await play(60, 250, 60), greaterThan(sounding));
    expect((await shown(60, 550), await shown(200, 550)), (2, 1));
    expect(loudness(), greaterThan(sounding), reason: 'no release reached it');
    await play(60, 250, 64);
    expect((await shown(60, 550), await shown(200, 550)), (4, 2));
    await click('0');
    expect(loudness(), lessThan(silent), reason: '0 silences it');
    await tap(buttonAt(380, 250));
    expect(await shown(200, 550), 2, reason: 'pack 64 0 sends nothing on');
    await tap(buttonAt(500, 250));
    expect(await shown(200, 550), 3, reason: 'pack 64 90 plays');
    expect(loudness(), greaterThan(sounding));
    await close();

    // ── poly ────────────────────────────────────────────────────────────────
    await open(
      '.poly',
      slug: 'poly',
      notes: 4,
      heading: 'poly hands each note a voice number',
    );
    await openLog();
    await clicks(['100', '60', '64', '67']);
    expect(
      (await shown(60, 440), await shown(140, 440), await shown(220, 440)),
      (3, 67, 100),
    );
    expect(loudness(), greaterThan(sounding), reason: 'three saws on master');
    await click('71');
    expect(await listAt(60, 500), '71 100', reason: 'no free voice');
    // Note 2.
    expect(await listAt(340, 500), '1 71 100', reason: 'the oldest gave way');
    await logged(['voice: 1 60 100', 'voice: 1 60 0', 'voice: 1 71 100']);
    await closeLog();
    // Note 3.
    await clicks(['0', '64']);
    expect((await shown(60, 440), await shown(220, 440)), (2, 0));
    expect(await listAt(340, 500), '2 64 0');
    await click('71');
    expect(await listAt(60, 500), '71 0');
    expect(await listAt(340, 500), '1 71 0');
    await click('stop');
    expect(await listAt(340, 500), '3 67 0');
    expect(loudness(), lessThan(silent), reason: 'every voice released');
    await close();

    // ── sustain ─────────────────────────────────────────────────────────────
    await open(
      '.sustain',
      slug: 'sustain',
      notes: 4,
      heading: 'sustain holds note releases back while its pedal is down',
    );
    // Note 1.
    expect(await play(60, 260, 60), greaterThan(sounding));
    expect((await shown(60, 420), await shown(170, 420)), (60, 0));
    expect(loudness(), lessThan(silent));
    // Note 2.
    await tap(toggleAt(380, 260));
    await play(60, 260, 64);
    expect(await shown(60, 420), 64);
    expect(await shown(170, 420), isNonZero);
    expect(loudness(), greaterThan(sounding), reason: 'the release is held');
    await play(60, 260, 67);
    await play(60, 260, 62);
    await openLog();
    await tap(toggleAt(380, 260));
    expect((await shown(60, 420), await shown(170, 420)), (67, 0));
    expect(loudness(), lessThan(silent));
    await logged(['sustain: 62 0', 'sustain: 64 0', 'sustain: 67 0']);
    await closeLog();
    // Note 3.
    await tap(toggleAt(380, 260));
    await play(60, 260, 60);
    expect(await shown(170, 420), isNonZero);
    await click('flush');
    expect(await shown(170, 420), 0, reason: 'flush sends it now');
    await play(60, 260, 64);
    await click('clear');
    await tap(toggleAt(380, 260));
    expect(await shown(170, 420), isNonZero, reason: 'clear sent nothing');
    expect(loudness(), greaterThan(sounding));
    await close();

    // ── borax ───────────────────────────────────────────────────────────────
    await open(
      '.borax',
      slug: 'borax',
      notes: 4,
      heading: 'borax measures a stream of notes',
    );
    Future<List<double>> top() async => [
      for (var i = 0; i < 5; i++) await shown(60.0 + 110 * i, 550),
    ];
    // Note 1: a key held for at least 150 ms.
    final held = Stopwatch()..start();
    expect(
      await play(60, 340, 60, hold: const Duration(milliseconds: 150)),
      greaterThan(sounding),
    );
    held.stop();
    expect((await top()).take(3), [1, 1, 0]);
    expect(await shown(60, 610), 1, reason: 'one note ended');
    expect(
      await shown(170, 610, type: '.f'),
      inInclusiveRange(140, held.elapsedMilliseconds + 20),
      reason: 'how long the key was held',
    );
    // Note 2.
    await play(60, 340, 64);
    expect((await top()).take(3), [2, 1, 0]);
    expect(await shown(280, 610), 1, reason: 'one delta time');
    expect(await shown(390, 610, type: '.f'), greaterThan(0));
    await click('delta');
    expect(await shown(280, 610), 2);
    // Note 3.
    await clicks(['60', '64', '67']);
    expect(await top(), [5, 3, 3, 67, 100]);
    expect(
      tester.widget<PatchKeyboard>(find.byType(PatchKeyboard)).held.keys,
      unorderedEquals([60, 64, 67]),
      reason: 'the keys stay down',
    );
    await clicks(['0', '64']);
    expect(await top(), [4, 2, 2, 64, 0]);
    await click('100');
    await tap(buttonAt(200, 430));
    expect(await top(), [5, 3, 0, 67, 0]);
    await play(60, 340, 72);
    expect((await top()).take(3), [1, 1, 0], reason: 'counting again');
    await close();

    // ── offer ───────────────────────────────────────────────────────────────
    await open(
      '.offer',
      slug: 'offer',
      notes: 4,
      heading: 'offer stores pairs of ints',
    );
    await clicks(['72', '60']);
    expect(await shown(60, 490), 0, reason: 'storing sends nothing');
    await click('60');
    expect(await shown(60, 490), 72);
    await clicks(['72', '79', '67']);
    await tap(buttonAt(300, 320));
    await openLog();
    await tap(buttonAt(60, 320));
    expect(await shown(60, 490), 76);
    await logged(['offer: 79', 'offer: 76']);
    await closeLog();
    await click('67');
    expect(await shown(60, 490), 79, reason: 'the bang deleted nothing');
    await click('clear');
    await click('60');
    expect(await shown(60, 490), 79, reason: 'no pair is left');
    await close();

    // ── mpeconfig, mpeformat and mpeparse ───────────────────────────────────
    await open(
      '.mpeformat',
      slug: 'mpeconfig-mpeparse-mpeformat',
      notes: 5,
      heading: 'MPE, MIDI Polyphonic Expression',
    );
    // With a loopback, waits until mpeparse's box at ([x], [y]) shows
    // [expected], read back from the wire.
    Future<void> back(double x, double y, String expected) async {
      if (loop == null) return;
      Future<String> read() async =>
          x == 60 ? await listAt(x, y) : (await shown(x, y)).toInt().toString();
      for (var i = 0; i < 200 && await read() != expected; i++) {
        await pause(2);
      }
      expect(await read(), expected, reason: 'read back by mpeparse');
    }

    await click('15');
    expect(await listAt(60, 410), '176 6 15');
    await click('2');
    await tap(buttonAt(60, 540));
    expect(await listAt(60, 790), '145 60 100');
    await back(60, 1070, '60 100');
    await back(410, 1070, '2');
    await back(490, 1070, '1');
    await click('8363');
    expect(await listAt(60, 790), '225 43 65');
    await back(170, 1070, '8363');
    await click('90');
    expect(await listAt(60, 790), '209 90');
    await back(250, 1070, '90');
    await click('30');
    expect(await listAt(60, 790), '177 74 30');
    await back(330, 1070, '30');
    await click('3');
    await tap(buttonAt(280, 540));
    expect(await listAt(60, 790), '146 64 90');
    await back(410, 1070, '3');
    await clicks(['2', '60']);
    expect(await listAt(60, 790), '145 60 0');
    await back(60, 1070, '60 0');
    await close();

    // The only errors a host may add are RtMidi's when it has no MIDI system
    // at all (a CI runner without an ALSA sequencer); then the badge is up.
    final errors = [
      for (final e in notices.log.entries)
        if (e.level == phi.LogLevel.error) e.text,
    ];
    expect(errors.where((e) => !isMidiDriverUnavailable(e)), isEmpty);
    expect(
      find.byKey(LogPanelToggle.badgeKey),
      errors.isEmpty ? findsNothing : findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await engine.dispose();
    await yse.dispose();
    notices.dispose();
  });
}
