import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_bang_square.dart';
import 'package:phi/design/widgets/patcher/patch_list_box.dart';
import 'package:phi/design/widgets/patcher/patch_message_box.dart';
import 'package:phi/design/widgets/patcher/patch_note_box.dart';
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

/// End-to-end proof of the **MIDI output tutorials** (issue #509) through the
/// real [PhiApp]: real rail navigation, fonts and layout, the real asset
/// bundle, the real patcher engine ([RealPatcherGateway] on an offline libyse
/// session) and the real engine log feeding the log panel. Only the audio
/// device and the app's own MIDI gateway are fakes.
///
/// The seven tutorials (notes; controllers; programs and pressure; pitch
/// bend; RPN and NRPN; raw bytes, midiformat and SysEx; flush and midiflush)
/// are opened from the palette's Tutorials tab by searching for a type they
/// cover. The test checks that the notes render, nothing overlaps and every
/// list box shows its list uncut, and plays each one with real taps.
///
/// Each tutorial sends through `.midiout 0` and shows what comes back on
/// input port 0 with `.xmidiin 0`. Where both port 0s are ALSA's `Midi
/// Through` ([MidiLoopback]), the canvas shows the bytes every tap put on the
/// wire, and the test reads them there and in the log panel. Elsewhere
/// (Windows, CI runners) it checks what the patch shows without a port.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: every MIDI output tutorial opens from the Tutorials '
      'tab and does what its notes say', (tester) async {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
    addTearDown(System.instance.close);

    // The tutorials send on output port 0 and listen on input port 0: the
    // loopback must be both.
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
      // print back writes to the engine log.
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
          newLocationPath: '/projects/midi-output-tutorials.phi',
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

    void render([int blocks = 1]) {
      for (var i = 0; i < blocks; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
      }
    }

    // Renders with real pauses: a .midiout opens its port on a background
    // thread, a message reaches the wire from the sender thread, and what
    // comes back reaches the patch on a later block.
    Future<void> pause([int steps = 20]) async {
      for (var i = 0; i < steps; i++) {
        render();
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
      // Mounted while open (#528): .xmidiin drains its port only in a
      // mounted patch's blocks. libyse sets the sound up in wall-clock time,
      // so render with real pauses until it is in the mix (#525). Then give
      // the port loadbang asked for time to open.
      final instance = tutorial.instanceId;
      for (var i = 0; i < 5000; i++) {
        if (gateway.isSourceReady(instance)) break;
        render();
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
    // wall-clock time, and only then gives its MIDI input subscription back.
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
    Future<void> click(double x, double y) async => tap(
      find.descendant(
        of: nodeAt('.m', x, y),
        matching: find.byType(PatchMessageBox),
      ),
    );
    Future<void> clicks(List<(double, double)> at) async {
      for (final (x, y) in at) {
        await click(x, y);
      }
    }

    // Lets a few blocks run and the surface's live-value poll come due.
    Future<void> settle() async {
      render(5);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
    }

    // What the number box at ([x], [y]) shows on the canvas.
    Future<double> shown(String type, double x, double y) async {
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

    // With a loopback, waits until the monitor list box at ([x], [y]) shows
    // [bytes]: the last message the taps before it sent, back from the wire.
    Future<void> back(double x, double y, List<int> bytes) async {
      if (loop == null) return;
      final expected = bytes.join(' ');
      for (var i = 0; i < 200 && await listAt(x, y) != expected; i++) {
        await pause(2);
      }
      expect(await listAt(x, y), expected, reason: 'back from the wire');
    }

    // ── noteon, noteoff and xnoteout ────────────────────────────────────────
    await open(
      '.xnoteout',
      slug: 'noteon-noteoff',
      notes: 6,
      heading: 'xnoteout builds both',
    );
    await clicks([(60, 230), (60, 350)]);
    expect(await shown('.i', 60, 290), 100);
    await back(60, 960, [144, 60, 100]);
    await click(60, 490);
    await back(60, 960, [153, 36, 100]);
    await clicks([(280, 490), (390, 490)]);
    await back(60, 960, [128, 60, 40]);
    await clicks([(60, 630), (390, 630), (170, 630), (390, 630)]);
    await back(60, 960, [128, 67, 64]);
    await close();

    // ── controlchange and xctlout ───────────────────────────────────────────
    await open(
      '.xctlout',
      slug: 'controlchange',
      notes: 6,
      heading: 'the coarse half on a controller 0-31',
    );
    await click(170, 230);
    expect(await shown('.i', 60, 370), 64);
    await back(60, 970, [176, 1, 64]);
    await click(390, 370);
    await back(60, 970, [176, 64, 127]);
    await click(280, 510);
    expect(await shown('.i', 60, 650), 16383);
    await back(60, 970, [176, 33, 127]);
    await close();

    // ── programchange, channelpressure and polypressure ─────────────────────
    await open(
      '.polypressure',
      slug: 'programchange-pressure',
      notes: 6,
      heading: 'their message is two bytes long',
    );
    await click(170, 250);
    await back(60, 850, [192, 5]);
    await click(170, 390);
    await back(60, 850, [208, 90]);
    await clicks([(60, 530), (280, 530)]);
    await back(60, 850, [160, 60, 70]);
    await close();

    // ── bendout, xbendout and xbendout2 ─────────────────────────────────────
    await open(
      '.xbendout2',
      slug: 'bendout',
      notes: 6,
      heading: 'xbendout2 takes the two bytes apart',
    );
    await click(280, 250);
    await back(60, 990, [224, 0, 127]);
    await click(170, 390);
    expect(await shown('.i', 60, 530), 8192);
    await back(60, 990, [224, 0, 64]);
    await clicks([(60, 670), (170, 670)]);
    await back(60, 990, [224, 100, 64]);
    await close();

    // ── rpnout and nrpnout ──────────────────────────────────────────────────
    await open(
      '.nrpnout',
      slug: 'rpnout-nrpnout',
      notes: 6,
      heading: 'which mean the same on every device',
    );
    // The log panel shows what print back writes.
    final errorsBefore = [
      for (final e in notices.log.entries)
        if (e.level == phi.LogLevel.error) e.text,
    ];
    expect(errorsBefore.where((e) => !isMidiDriverUnavailable(e)), isEmpty);
    await tap(find.byKey(LogPanelToggle.toggleKey));
    expect(find.byType(LogPanel), findsOneWidget, reason: 'the log toggle');
    if (find.byKey(LogPanel.clearKey).evaluate().isNotEmpty) {
      await tap(find.byKey(LogPanel.clearKey));
    }
    Finder logRow(String text) => find.descendant(
      of: find.byType(LogPanel),
      matching: find.textContaining(text),
    );
    await clicks([(60, 230), (170, 230)]);
    await back(60, 790, [176, 38, 0]);
    if (loop != null) {
      for (final row in ['176 101 0', '176 100 0', '176 6 12', '176 38 0']) {
        for (
          var i = 0;
          i < 100 && logRow('back: $row').evaluate().isEmpty;
          i++
        ) {
          await pause(2);
          await tester.pumpAndSettle();
        }
        expect(logRow('back: $row'), findsWidgets, reason: row);
      }
    }
    await tap(find.byKey(LogPanelToggle.toggleKey));
    expect(find.byType(LogPanel), findsNothing);
    await clicks([(60, 450), (170, 450)]);
    await back(60, 790, [177, 38, 0]);
    await close();

    // ── midiout, midiformat and sxformat ────────────────────────────────────
    await open(
      '.sxformat',
      slug: 'midiout-midiformat-sxformat',
      notes: 7,
      heading: 'a single number is not sent',
    );
    await click(60, 230);
    expect(await listAt(300, 290), '144 60 100');
    await back(60, 1090, [144, 60, 100]);
    await click(60, 370);
    expect(await listAt(300, 490), '144 60 100');
    await click(390, 370);
    expect(await listAt(300, 490), '192 5');
    await back(60, 1090, [192, 5]);
    await clicks([(170, 570), (60, 570)]);
    expect(await listAt(60, 830), '240 125 1 64 247');
    await clicks([(170, 710), (60, 710)]);
    expect(await listAt(60, 830), '240 125 16 32 80 247');
    await back(60, 1090, [240, 125, 16, 32, 80, 247]);
    await close();

    // ── flush and midiflush ─────────────────────────────────────────────────
    await open(
      '.midiflush',
      slug: 'midiflush-flush',
      notes: 6,
      heading: 'a bang releases exactly those',
    );
    await clicks([(60, 230), (60, 290), (170, 290), (280, 290)]);
    expect(await shown('.i', 60, 470), 67);
    expect(await shown('.i', 160, 470), 100);
    await tap(buttonAt(60, 350));
    expect(await shown('.i', 60, 470), 67);
    expect(await shown('.i', 160, 470), 0);
    await back(60, 990, [144, 67, 0]);
    await clicks([(60, 610), (170, 610)]);
    await back(60, 990, [145, 48, 100]);
    await tap(buttonAt(300, 670));
    await back(60, 990, [129, 48, 0]);
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
