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

/// End-to-end proof of the **MIDI input tutorials** (issue #508) through the
/// real [PhiApp]: real rail navigation, fonts and layout, the real asset
/// bundle, the real patcher engine ([RealPatcherGateway] on an offline libyse
/// session) and the real engine log feeding the log panel. Only the audio
/// device and the app's own MIDI gateway are fakes.
///
/// The seven tutorials (raw bytes and midiparse; notes; controllers; bend
/// and pressure; programs, clock and SysEx; RPN and NRPN; the port listing)
/// are opened from the palette's Tutorials tab by searching for a type they
/// cover. The test checks that the notes render, nothing overlaps and every
/// list box shows its list uncut, and plays midiparse and midiinfo with real
/// taps.
///
/// The keyboard is played through a real MIDI port: libyse has no call that
/// injects MIDI into a patch, so [MidiLoopback] sends into the ALSA `Midi
/// Through` port, which the tutorials' objects hear on port 0. A machine
/// without that port (Windows, CI runners) skips the keyboard steps and still
/// runs everything else.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: every MIDI input tutorial opens from the Tutorials '
      'tab and does what its notes say', (tester) async {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
    addTearDown(System.instance.close);

    // The tutorials listen on port 0: the loopback must be that port.
    final opened = MidiLoopback.open();
    final loop = opened != null && opened.inputPort == 0 ? opened : null;
    addTearDown(() => opened?.close());
    if (loop == null) {
      // ignore: avoid_print
      print('no MIDI loopback on input port 0: keyboard steps skipped');
    }

    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final yse = FakeYseGateway();
    final gateway = RealPatcherGateway();
    final engine = PhiEngine(
      yse,
      patcherGateway: gateway,
      midiGateway: FakeMidiGateway(),
      // print in the midiinfo tutorial writes to the engine log.
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
          newLocationPath: '/projects/midi-input-tutorials.phi',
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
      // Mounted while open (#528), and a MIDI input object drains its port
      // only in a mounted patch's blocks. libyse sets the sound up in
      // wall-clock time, so render with real pauses until it is in the mix
      // (#525).
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

    // A closed tutorial's patch is destroyed by libyse a moment later, in
    // wall-clock time, and only then gives its MIDI input subscriptions back:
    // at most eight objects can listen to one port (yse-soundengine#1246).
    // The app's audio thread runs on its own; this offline session renders,
    // with real pauses, until the next tutorial can have them.
    Future<void> close() async {
      expectListBoxesUncut(tester, where: library.tutorial?.slug ?? '');
      await tap(find.byKey(PatchTutorialBar.closeKey));
      for (var i = 0; i < 100; i++) {
        loudness(1);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 3)),
        );
      }
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

    // MIDI and background scans arrive in wall-clock time: render with real
    // pauses until [done] holds.
    Future<void> renderUntil(
      Future<bool> Function() done, {
      String what = 'the message',
    }) async {
      for (var i = 0; i < 200; i++) {
        if (await done()) return;
        loudness(2);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      expect(await done(), isTrue, reason: '$what arrived');
    }

    // Plays [bytes] into the tutorial's port, as a keyboard would, and waits
    // until [arrived] holds.
    Future<void> play(List<int> bytes, Future<bool> Function() arrived) async {
      loop!.send(bytes);
      await renderUntil(arrived, what: '$bytes');
    }

    // ── raw MIDI and midiparse ──────────────────────────────────────────────
    await open(
      '.midiparse',
      slug: 'midiin-midiparse',
      notes: 5,
      heading: 'splits them into notes, controllers',
    );
    for (final x in [60.0, 170.0, 280.0]) {
      await tap(messageAt(x, 370));
    }
    expect(await listAt(60, 510), '60 100');
    expect(await shown('.i', 360, 580), 1);
    await tap(messageAt(170, 370));
    await tap(messageAt(390, 370));
    expect(await listAt(60, 510), '60 0', reason: 'running status');
    if (loop != null) {
      await play([
        144,
        64,
        127,
      ], () async => await listAt(300, 290) == '144 64 127');
      expect(await shown('.i', 60, 290), 127);
      expect(await listAt(60, 510), '64 127');
      await play([
        176,
        74,
        127,
      ], () async => await listAt(320, 510) == '74 127');
      await play([
        161,
        127,
        127,
      ], () async => await listAt(190, 510) == '127 127');
      await play([224, 0, 127], () async => await shown('.i', 260, 580) == 127);
      await play([
        240,
        67,
        16,
        1,
        2,
        247,
      ], () async => await listAt(460, 580) == '240 67 16 1 2 247');
      expect(await listAt(300, 290), '240 67 16 1 2 247');
    }
    await close();

    // ── notein and xnotein ──────────────────────────────────────────────────
    await open(
      '.xnotein',
      slug: 'notein',
      notes: 4,
      heading: 'also reports the release velocity',
    );
    expect(loudness(), 0, reason: 'silent until a key is played');
    if (loop != null) {
      await play([144, 57, 110], () async => await shown('.i', 60, 310) == 57);
      expect(await shown('.i', 160, 310), 110);
      expect(await shown('.i', 260, 310), 1);
      expect(loudness(), greaterThan(0.05), reason: 'the saw on master');
      await play([128, 57, 20], () async => await shown('.i', 160, 310) == 0);
      loudness(20);
      expect(loudness(), lessThan(1e-3), reason: 'the release');
      expect(await shown('.i', 260, 750), 20, reason: 'release velocity');
      await play([153, 38, 70], () async => await shown('.i', 380, 310) == 38);
      expect(await shown('.i', 480, 310), 10);
      await play([137, 38, 0], () async => await shown('.i', 160, 310) == 0);
    }
    await close();

    // ── ctlin and xctlin ────────────────────────────────────────────────────
    await open(
      '.xctlin',
      slug: 'ctlin',
      notes: 4,
      heading: 'pairs controllers 0-31 with their fine',
    );
    expect(loudness(), 0, reason: 'silent until the volume moves');
    if (loop != null) {
      await play([176, 1, 127], () async => await shown('.i', 60, 310) == 127);
      expect(await shown('.f', 60, 510), closeTo(4000, 0.01));
      expect(await shown('.i', 60, 770), 16256);
      await play([
        176,
        33,
        127,
      ], () async => await shown('.i', 60, 770) == 16383);
      await play([176, 7, 100], () async => await shown('.i', 160, 310) == 7);
      expect(await shown('.f', 240, 510), closeTo(100 / 127 * 0.2, 1e-6));
      expect(loudness(), greaterThan(0.05), reason: 'the saw on master');
      await play([176, 7, 0], () async => await shown('.f', 240, 510) == 0);
      loudness(20);
      expect(loudness(), lessThan(1e-3));
    }
    await close();

    // ── bend and pressure ───────────────────────────────────────────────────
    await open(
      '.polyin',
      slug: 'bendin-touchin',
      notes: 4,
      heading: 'polyin a pressure per key',
    );
    if (loop != null) {
      await play([
        239,
        127,
        127,
      ], () async => await shown('.i', 300, 290) == 16383);
      expect(await shown('.i', 60, 290), 127);
      expect(await shown('.i', 160, 290), 16);
      expect(await shown('.f', 300, 410), closeTo(2, 0.001));
      expect(await shown('.i', 160, 430), 127);
      await play([224, 0, 0], () async => await shown('.i', 300, 290) == 0);
      expect(await shown('.f', 300, 410), -2);
      await play([208, 127], () async => await shown('.i', 60, 570) == 127);
      await play([175, 127, 99], () async => await shown('.i', 400, 570) == 99);
      expect(await shown('.i', 300, 570), 127);
      expect(await shown('.i', 500, 570), 16);
    }
    await close();

    // ── programs, clock and SysEx ───────────────────────────────────────────
    await open(
      '.sysexin',
      slug: 'pgmin-rtin-sysexin',
      notes: 5,
      heading: 'sends every byte of a system-exclusive',
    );
    if (loop != null) {
      await play([192, 2], () async => await shown('.i', 60, 470) == 2);
      expect(await shown('.i', 160, 470), 140);
      expect(await shown('.i', 260, 470), 3200);
      expect(await shown('.i', 60, 290), 3);
      // The longest dump the box has room for.
      await play(
        [240, 125, 127, 127, 127, 127, 127, 247],
        () async => await listAt(360, 470) == '240 125 127 127 127 127 127 247',
      );
      await play([250], () async => await shown('.i', 60, 620) == 250);
      for (var i = 0; i < 23; i++) {
        loop.send([248]);
      }
      await play([248], () async => await shown('.i', 160, 740) == 24);
      expect(await shown('.i', 160, 860), 1, reason: 'one quarter note');
      await play([252], () async => await shown('.i', 60, 620) == 252);
    }
    await close();

    // ── RPN and NRPN ────────────────────────────────────────────────────────
    await open(
      '.nrpnin',
      slug: 'rpnin-nrpnin',
      notes: 4,
      heading: 'select a registered parameter (RPN)',
    );
    if (loop != null) {
      loop
        ..send([176, 101, 0])
        ..send([176, 100, 2]);
      await play([176, 6, 64], () async => await shown('.i', 60, 270) == 8192);
      expect(await shown('.i', 160, 270), 2, reason: 'coarse tuning');
      expect(await shown('.i', 60, 390), 64);
      await play([
        176,
        38,
        127,
      ], () async => await shown('.i', 160, 390) == 127);
      loop
        ..send([176, 99, 127])
        ..send([176, 98, 127]);
      await play([
        176,
        6,
        127,
      ], () async => await shown('.i', 60, 530) == 16256);
      expect(await shown('.i', 160, 530), 16383);
    }
    await close();

    // ── midiinfo ────────────────────────────────────────────────────────────
    await open(
      '.midiinfo',
      slug: 'midiinfo',
      notes: 4,
      heading: 'then an index and a name for each port',
    );
    Finder logRow(String text) => find.descendant(
      of: find.byType(LogPanel),
      matching: find.textContaining(text),
    );
    // The tutorials before this one logged no engine error (#539). The one
    // error a host may add is RtMidi's when it has no MIDI input system at
    // all (a CI runner without an ALSA sequencer): then the badge is up and
    // the toggle opens the log filtered to errors, so show everything.
    final errors = [
      for (final e in notices.log.entries)
        if (e.level == phi.LogLevel.error) e.text,
    ];
    expect(errors.where((e) => !isMidiInDriverUnavailable(e)), isEmpty);
    expect(
      find.byKey(LogPanelToggle.badgeKey),
      errors.isEmpty ? findsNothing : findsOneWidget,
    );
    await tap(find.byKey(LogPanelToggle.toggleKey));
    expect(find.byType(LogPanel), findsOneWidget, reason: 'the log toggle');
    if (find.byKey(LogPanel.clearKey).evaluate().isNotEmpty) {
      await tap(find.byKey(LogPanel.clearKey));
    }
    await tap(buttonAt(60, 230));
    final inputs = System.instance.midiInDeviceCount;
    expect(await shown('.i', 300, 370), inputs);
    if (inputs > 0) {
      expect(await listAt(60, 430), startsWith('${inputs - 1} '));
      await renderUntil(() async => logRow('ports: 0 ').evaluate().isNotEmpty);
    }
    await tap(messageAt(260, 230));
    await tap(buttonAt(60, 230));
    expect(await shown('.i', 300, 370), System.instance.midiOutDeviceCount);
    await tap(messageAt(150, 230));
    await tap(messageAt(380, 230));
    await renderUntil(() async => await shown('.i', 300, 370) == inputs);
    await tap(find.byKey(LogPanelToggle.toggleKey));
    expect(find.byType(LogPanel), findsNothing);
    await close();

    await tester.pumpWidget(const SizedBox());
    await engine.dispose();
    await yse.dispose();
    notices.dispose();
  });
}
