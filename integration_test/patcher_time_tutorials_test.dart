import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_bang_square.dart';
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
import 'package:phi/surfaces/patcher/nodes/slider_node_body.dart';
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
import '../test/surfaces/patcher/test_support/open_tutorial_by_search.dart';

/// End-to-end proof of the **clock, delay and ramp tutorials** (issue #497)
/// through the real [PhiApp]: real rail navigation, fonts and layout, the
/// real asset bundle and the real patcher engine ([RealPatcherGateway] on an
/// offline libyse session). Only the audio device and MIDI are fakes.
///
/// The metro, delay, pipe, line/bline, speedlim/qlim, timer/clocker and
/// thresh/quickthresh tutorials are opened from the palette's Tutorials tab,
/// once through each type they cover. The test checks that the notes render
/// and nothing overlaps, then plays the patches with real taps and drags and
/// reads the results back from the canvas and the engine, the way the notes
/// tell the user to. On libYSE 3.1.0 delay, pipe, line, speedlim, qlim and
/// the thresh pair keep audio time, so the test renders blocks for them (the
/// tutorial is mounted while open, #528); metro, timer and clocker keep
/// wall-clock time, so it waits real time for those.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Finder message(String text) => find.descendant(
    of: find.byType(PatchMessageBox),
    matching: find.text(text),
  );

  testWidgets('patcher: every clock, delay and ramp tutorial opens from the '
      'Tutorials tab and does what its notes say', (tester) async {
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
          newLocationPath: '/projects/time-tutorials.phi',
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

    // Lets [ms] milliseconds of real time pass: metro, timer and clocker keep
    // wall-clock time, not the offline render's.
    Future<void> wait(int ms) async {
      await tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: ms)),
      );
      await tester.pump();
    }

    // Opens every other type a tutorial covers, and closes it again.
    Future<void> openRest(
      List<String> types, {
      required String slug,
      required int notes,
      required String heading,
    }) async {
      for (final type in types) {
        await open(type, slug: slug, notes: notes, heading: heading);
        await close();
      }
    }

    // [ms] milliseconds of audio: what delay, pipe, line, speedlim, qlim and
    // the thresh pair count. One block is 128 frames at 48 kHz.
    void audio(double ms) => loudness((ms * 48 / 128).ceil());

    int whole(int id) => int.parse(value(id));

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

    // ── metro: on and off, the interval while running, bang and stop ───────
    var at = await open(
      '.metro',
      slug: 'metro',
      notes: 4,
      heading: 'A steady pulse',
    );
    final ticks = at('.i', 60, 400);
    expect(value(at('.i', 360, 230)), '500', reason: 'loadmess on load');
    await tap(toggleAt(60, 160));
    expect(whole(ticks), 1, reason: 'a tick the moment it starts');
    await wait(1100);
    expect(whole(ticks), inInclusiveRange(2, 4), reason: 'every 500 ms');
    await tap(message('125'));
    var before = whole(ticks);
    await wait(600);
    expect(whole(ticks) - before, greaterThan(2), reason: 'four times as fast');
    await tap(toggleAt(60, 160));
    final stopped = whole(ticks);
    await wait(300);
    expect(whole(ticks), stopped, reason: '0 stops it');
    // Back to one tick a second, so that no second tick lands within the
    // real time a tap and its settling take: metro keeps wall-clock time.
    await tap(message('1000'));
    expect(value(at('.i', 360, 230)), '1000');
    await tap(message('bang'));
    expect(whole(ticks), stopped + 1, reason: 'bang starts it, at once');
    await tap(message('stop'));
    before = whole(ticks);
    await wait(300);
    expect(whole(ticks), before, reason: 'stop stops it');
    expect(await shown('.i', 60, 400), before, reason: 'the count on screen');
    await close();

    // ── delay: later, restarted, cancelled, either inlet, chained ───────────
    const delayHeading = 'delay sends a bang a set time after it gets one';
    at = await open('.delay', slug: 'delay', notes: 5, heading: delayHeading);
    final arrived = at('.i', 60, 340);
    final clicks = at('.i', 220, 340);
    await tap(buttonAt(60, 160));
    expect((value(clicks), value(arrived)), ('1', '0'));
    // Audio-time checks keep a margin: a click reaches the engine through
    // its message queue, so the wait starts within a block or so of it.
    audio(700);
    expect(value(arrived), '0', reason: 'not yet');
    audio(600);
    expect(value(arrived), '1', reason: 'a second later');
    expect(await shown('.i', 60, 340), 1, reason: 'on screen');
    for (var i = 0; i < 3; i++) {
      await tap(buttonAt(60, 160));
      audio(400);
    }
    expect(value(arrived), '1', reason: 'each bang starts the wait again');
    audio(1000);
    expect(value(arrived), '2');
    await tap(buttonAt(60, 160));
    audio(500);
    await tap(message('stop'));
    audio(1000);
    expect(value(arrived), '2', reason: 'stop cancels');
    await tap(message('2000'));
    audio(1500);
    expect(value(arrived), '2');
    audio(800);
    expect(value(arrived), '3', reason: '2000 sets the time and starts');
    await tap(message('250'));
    await tap(buttonAt(60, 160));
    audio(550);
    expect(value(arrived), '4', reason: '250 ms');
    await tap(buttonAt(60, 440));
    audio(750);
    expect((value(at('.i', 340, 490)), value(at('.i', 340, 560))), ('1', '0'));
    audio(500);
    expect((value(at('.i', 340, 490)), value(at('.i', 340, 560))), ('1', '1'));
    await close();

    // ── pipe: every value kept, its own delay, flush, clear, a list ─────────
    const pipeHeading = 'Unlike delay it keeps every value';
    at = await open('.pipe', slug: 'pipe', notes: 5, heading: pipeHeading);
    final piped = at('.f', 60, 340);
    final count = at('.i', 170, 440);
    for (final m in ['1', '2', '3.5']) {
      await tap(message(m));
      audio(100);
    }
    audio(550);
    expect(value(count), '0', reason: 'nothing yet');
    final seen = <double>[];
    for (var i = 0; i < 40 && whole(count) < 3; i++) {
      audio(20);
      final v = read(piped);
      if (v != 0 && (seen.isEmpty || seen.last != v)) seen.add(v);
    }
    expect(seen, [1, 2, 3.5], reason: 'all three, in order');
    expect(value(count), '3');
    await tap(message('1000'));
    await tap(message('1'));
    await tap(message('250'));
    await tap(message('2'));
    audio(550);
    expect(read(piped), 2, reason: '2 overtakes 1');
    audio(800);
    expect(read(piped), 1);
    await tap(message('1'));
    await tap(message('flush'));
    expect(value(count), '6', reason: 'flushed at once');
    await tap(message('2'));
    await tap(message('clear'));
    audio(500);
    expect(value(count), '6', reason: 'cleared');
    await tap(buttonAt(60, 520));
    audio(900);
    expect(value(at('.l', 60, 690)), '60 64 67', reason: 'the list waited');
    await close();

    // ── line bline: a glide, the grain, a function stepped by bangs ─────────
    const lineHeading = 'line glides to a target over a time';
    at = await open(
      '.line',
      slug: 'line-bline',
      notes: 5,
      heading: lineHeading,
    );
    await tap(message('1'));
    final path = <double>[];
    final coarse = <double>{};
    for (var i = 0; i < 12; i++) {
      audio(100);
      path.add(await shown('.f', 110, 340));
      coarse.add(read(at('.f', 270, 340)));
    }
    expect(path.last, 1, reason: 'line arrives in a second: $path');
    expect(
      path.where((v) => v > 0 && v < 1),
      hasLength(greaterThan(5)),
      reason: 'it glides on the canvas: $path',
    );
    for (var i = 1; i < path.length; i++) {
      expect(path[i], greaterThanOrEqualTo(path[i - 1]), reason: '$path');
    }
    expect(
      coarse.where((v) => v > 0 && v < 1),
      hasLength(3),
      reason: 'the grain of 250: $coarse',
    );
    expect(read(at('.slider', 60, 340)), 1, reason: 'the slider rose');
    expect(value(at('.i', 400, 380)), '1', reason: 'one arrival');
    await tap(buttonAt(60, 560));
    final walk = <double>[];
    for (var i = 0; i < 11; i++) {
      await tap(buttonAt(300, 560));
      walk.add(read(at('.f', 300, 740)));
    }
    expect(walk, [0, 0.25, 0.5, 0.75, 1, 0.75, 0.5, 0.375, 0.25, 0.125, 0]);
    expect(value(at('.i', 440, 780)), '1', reason: 'at the end');
    await tap(buttonAt(60, 560));
    await tap(toggleAt(400, 560));
    await wait(1400);
    await tap(toggleAt(400, 560));
    expect(value(at('.i', 440, 780)), '2', reason: 'metro played it through');
    await close();
    await openRest(
      ['.bline'],
      slug: 'line-bline',
      notes: 5,
      heading: lineHeading,
    );

    // ── speedlim qlim: a slider drag thinned, the last value held ───────────
    const limHeading = 'Both let at most one message through per interval';
    at = await open(
      '.speedlim',
      slug: 'speedlim-qlim',
      notes: 4,
      heading: limHeading,
    );
    // Drag the slider from its middle up and down for two seconds of audio.
    final track = tester.getRect(
      find.descendant(
        of: nodeAt('.slider', 60, 160),
        matching: find.byType(SliderNodeBody),
      ),
    );
    final pointer = await tester.startGesture(track.center);
    await tester.pump();
    for (var i = 0; i <= 80; i++) {
      final fraction = 0.5 + 0.4 * math.sin(i * math.pi / 20);
      await pointer.moveTo(
        Offset(track.center.dx, track.bottom - fraction * track.height),
      );
      await tester.pump();
      audio(25);
    }
    await pointer.up();
    await tester.pumpAndSettle();
    audio(600);
    final raw = whole(at('.i', 60, 440));
    final sped = whole(at('.i', 320, 390));
    final queued = whole(at('.i', 510, 390));
    expect(raw, greaterThan(40), reason: 'a number on every move');
    expect(sped, inInclusiveRange(3, 6), reason: 'twice a second');
    expect(queued, inInclusiveRange(sped, sped + 1));
    final last = read(at('.slider', 60, 160)) * 100;
    expect(read(at('.f', 430, 290)), closeTo(last, 1e-3), reason: 'held');
    expect(read(at('.f', 240, 290)), isNot(closeTo(last, 1e-3)));
    await tap(message('0'));
    expect(
      [
        for (final x in [60.0, 320.0, 510.0])
          value(at('.i', x, x == 60 ? 440 : 390)),
      ],
      ['0', '0', '0'],
    );
    await close();
    await openRest(
      ['.qlim'],
      slug: 'speedlim-qlim',
      notes: 4,
      heading: limHeading,
    );

    // ── timer clocker: a tap tempo, a stopwatch, the time so far ────────────
    const timerHeading = 'timer measures the time between a bang';
    at = await open(
      '.timer',
      slug: 'timer-clocker',
      notes: 5,
      heading: timerHeading,
    );
    for (var i = 0; i < 3; i++) {
      await tap(buttonAt(60, 160));
      if (i < 2) await wait(500);
    }
    final between = read(at('.f', 60, 340));
    expect(between, inInclusiveRange(480, 800), reason: 'between two taps');
    expect(read(at('.f', 60, 450)), closeTo(60000 / between, 1e-3));
    await tap(buttonAt(360, 160));
    await wait(300);
    await tap(buttonAt(460, 160));
    final lap = read(at('.f', 360, 280));
    expect(lap, inInclusiveRange(280, 600), reason: 'the stopwatch');
    await wait(200);
    await tap(buttonAt(460, 160));
    expect(read(at('.f', 360, 280)), greaterThan(lap + 150), reason: 'kept');
    await tap(toggleAt(60, 580));
    await wait(500);
    final elapsed = whole(at('.i', 60, 700));
    expect(elapsed, inInclusiveRange(300, 900), reason: 'the time so far');
    await tap(toggleAt(60, 580));
    await close();
    await openRest(
      ['.clocker'],
      slug: 'timer-clocker',
      notes: 5,
      heading: timerHeading,
    );

    // ── thresh quickthresh: a chord, by hand, a trickle ─────────────────────
    const threshHeading = 'Both collect numbers that arrive close together';
    at = await open(
      '.thresh',
      slug: 'thresh-quickthresh',
      notes: 4,
      heading: threshHeading,
    );
    final held = at('.l', 60, 340);
    final quick = at('.l', 300, 340);
    await tap(buttonAt(400, 160));
    audio(600);
    expect((value(held), value(quick)), ('60 64 67', '60 64 67'));
    for (final m in ['67', '64', '60']) {
      await tap(message(m));
    }
    audio(700);
    expect((value(held), value(quick)), ('67 64 60', '67 64 60'));
    expect((value(at('.i', 180, 440)), value(at('.i', 420, 440))), ('2', '2'));
    // The trickle: metro keeps real time, the groups audio time.
    await tap(toggleAt(60, 530));
    for (var i = 0; i < 20; i++) {
      await wait(50);
      audio(50);
    }
    await tap(toggleAt(60, 530));
    expect(value(at('.i', 180, 440)), '2', reason: 'thresh holds on');
    expect(whole(at('.i', 420, 440)), greaterThan(3), reason: 'quick groups');
    audio(600);
    final trickle = value(held).split(' ');
    expect(trickle.length, greaterThan(4), reason: 'one long list: $trickle');
    expect(trickle.first, '1');
    await close();
    await openRest(
      ['.quickthresh'],
      slug: 'thresh-quickthresh',
      notes: 4,
      heading: threshHeading,
    );

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
