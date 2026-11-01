import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_bang_square.dart';
import 'package:phi/design/widgets/patcher/patch_message_box.dart';
import 'package:phi/design/widgets/patcher/patch_note_box.dart';
import 'package:phi/design/widgets/patcher/patch_toggle_square.dart';
import 'package:phi/design/widgets/patcher/patch_xy_pad.dart';
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

/// End-to-end proof of the **stateful math tutorials** (issue #496) through
/// the real [PhiApp]: real rail navigation, fonts and layout, the real asset
/// bundle and the real patcher engine ([RealPatcherGateway] on an offline
/// libyse session). Only the audio device and MIDI are fakes.
///
/// The counter, accum, change/togedge, threshold and record, statistics,
/// slide/linedrive, div/swap/pong and cartopol/poltocar tutorials are opened
/// from the palette's Tutorials tab, once through each type they cover. The
/// test checks that the notes render and nothing overlaps, then plays the
/// patches with real taps and drags, waits real time for the metros and the
/// line, and reads the results back from the engine, the way the notes tell
/// the user to. The counter's step sequencer is heard on the master meter.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Finder message(String text) => find.descendant(
    of: find.byType(PatchMessageBox),
    matching: find.text(text),
  );

  testWidgets('patcher: every stateful math tutorial opens from the Tutorials '
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
          newLocationPath: '/projects/stateful-math.phi',
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

    // A press at [from], dragged through to [to] in two steps.
    Future<void> drag(Offset from, Offset to) async {
      final pointer = await tester.startGesture(from);
      await tester.pump();
      await pointer.moveTo(Offset.lerp(from, to, 0.5)!);
      await tester.pump();
      await pointer.moveTo(to);
      await tester.pump();
      await pointer.up();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
    }

    // Drags the slider at ([x], [y]) from its middle to [fraction] of its
    // height (0 the bottom, 1 the top).
    Future<void> slide(double x, double y, double fraction) async {
      final body = tester.getRect(
        find.descendant(
          of: nodeAt('.slider', x, y),
          matching: find.byType(SliderNodeBody),
        ),
      );
      await drag(
        body.center,
        Offset(body.center.dx, body.bottom - fraction * body.height),
      );
    }

    // The numbers in a list box.
    List<double> numbers(int id) => [
      for (final t in value(id).split(' ')) double.parse(t),
    ];

    // The button at ([x], [y]).
    Finder buttonAt(double x, double y) => find.descendant(
      of: nodeAt('.b', x, y),
      matching: find.byType(PatchBangSquare),
    );

    // Lets [ms] milliseconds of real time pass: metro and line tick in real
    // time, not in the offline render's.
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

    // ── counter: bangs, the step, reset, a range, a step sequencer ──────────
    const counterHeading = 'Each bang adds the step to the count';
    var at = await open(
      '.counter',
      slug: 'counter',
      notes: 6,
      heading: counterHeading,
    );
    expect(loudness(), lessThan(1e-4), reason: 'silent until switched on');
    final count = at('.i', 60, 270);
    for (final want in ['1', '2', '3']) {
      await tap(buttonAt(60, 160));
      expect(value(count), want);
    }
    await tap(message('20'));
    expect(value(count), '20', reason: 'a number sets the count');
    await tap(message('3'));
    await tap(buttonAt(60, 160));
    expect(value(count), '23', reason: 'step 3');
    await tap(message('-1'));
    await tap(buttonAt(60, 160));
    expect(value(count), '22', reason: 'counting down');
    await tap(message('reset'));
    expect(value(count), '22', reason: 'reset sends nothing');
    await tap(buttonAt(60, 160));
    expect(value(count), '-1', reason: 'the start value plus the step');
    final wrapped = <String>[];
    final folded = <String>[];
    for (var i = 0; i < 5; i++) {
      await tap(buttonAt(60, 350));
      wrapped.add(value(at('.i', 60, 510)));
      folded.add(value(at('.i', 170, 510)));
    }
    expect(wrapped, ['1', '2', '3', '0', '1'], reason: '% 4 wraps');
    expect(folded, ['1', '2', '3', '2', '1'], reason: 'pong 0 3 folds');
    // The sequencer: metro runs in real time, so give it real time to step.
    await tap(toggleAt(60, 590));
    final pitches = {
      for (final n in [60, 64, 67, 72]) 440 * math.pow(2, (n - 69) / 12),
    };
    final steps = <String>{};
    for (var i = 0; i < 10; i++) {
      await wait(100);
      steps.add(value(at('.i', 200, 740)));
      final hz = read(at('.f', 170, 920));
      expect(
        pitches.any((p) => (p - hz).abs() < 0.01),
        isTrue,
        reason: '$hz Hz is one of the four notes',
      );
    }
    expect(steps.length, greaterThan(2), reason: 'it steps');
    expect(
      int.parse(value(at('.i', 500, 910))),
      greaterThan(0),
      reason: 'bars',
    );
    expect(loudness(), greaterThan(0.02), reason: 'the sequence on master');
    await tap(toggleAt(60, 590));
    await close();

    // ── accum: add, multiply, replace, reset, a running sum, a fade ─────────
    const accumHeading = 'accum stores one number';
    at = await open('.accum', slug: 'accum', notes: 5, heading: accumHeading);
    expect(loudness(), lessThan(1e-4), reason: 'mounted (#528), but silent');
    final stored = at('.f', 60, 330);
    await tap(buttonAt(60, 220));
    expect(read(stored), 10, reason: 'the argument');
    await tap(message('5'));
    expect(read(stored), 10, reason: 'the middle inlet sends nothing');
    await tap(buttonAt(60, 220));
    expect(read(stored), 15);
    await tap(message('2'));
    await tap(buttonAt(60, 220));
    expect(read(stored), 30, reason: 'multiplied');
    await tap(message('100'));
    expect(read(stored), 100, reason: 'replaced and sent');
    await tap(message('reset'));
    await tap(buttonAt(60, 220));
    expect(read(stored), 10, reason: 'reset');
    for (final (m, want) in [('3', 3.0), ('4', 7.0), ('10', 17.0)]) {
      await tap(message(m));
      expect(read(at('.f', 60, 580)), want, reason: 'the running sum');
    }
    await tap(message('0'));
    expect(read(at('.f', 60, 580)), 0);
    for (var i = 0; i < 3; i++) {
      await tap(buttonAt(60, 660));
    }
    expect(read(at('.f', 60, 820)), closeTo(0.512, 1e-6), reason: '0.8 cubed');
    await close();

    // ── change togedge: repeats filtered, the moments around 0 ──────────────
    const changeHeading = 'change passes a number on only when it differs';
    at = await open(
      '.change',
      slug: 'change-togedge',
      notes: 5,
      heading: changeHeading,
    );
    // Drag slowly up the slider: press in the middle (the outlet sits on the
    // bottom edge), go down near the bottom, then climb in small moves.
    final track = tester.getRect(
      find.descendant(
        of: nodeAt('.slider', 60, 160),
        matching: find.byType(SliderNodeBody),
      ),
    );
    final pointer = await tester.startGesture(track.center);
    await tester.pump();
    for (var i = 0; i <= 24; i++) {
      final fraction = 0.05 + i * 0.9 / 24;
      await pointer.moveTo(
        Offset(track.center.dx, track.bottom - fraction * track.height),
      );
      await tester.pump();
    }
    await pointer.up();
    await tester.pumpAndSettle();
    final arrived = int.parse(value(at('.i', 300, 380)));
    final passed = int.parse(value(at('.i', 420, 380)));
    expect(read(at('.f', 140, 330)), 4, reason: 'round(0.95 × 4)');
    expect(passed, greaterThan(0));
    expect(arrived, greaterThan(passed), reason: 'repeats held back');
    final on = at('.i', 360, 650);
    final off = at('.i', 470, 650);
    for (final m in ['1', '2', '0', '0']) {
      await tap(message(m));
    }
    expect(read(at('.f', 60, 600)), 0);
    expect(
      (value(at('.i', 150, 700)), value(at('.i', 250, 700))),
      ('1', '1'),
      reason: 'left 0 once, came back once',
    );
    expect((value(on), value(off)), ('1', '1'), reason: '1 2 is one on');
    await tap(message('0.5'));
    expect((value(on), value(off)), ('2', '1'), reason: '0.5 counts as on');
    await tap(buttonAt(500, 480));
    expect((value(on), value(off)), ('2', '2'), reason: 'the button flips');
    await close();
    await openRest(
      ['.togedge'],
      slug: 'change-togedge',
      notes: 5,
      heading: changeHeading,
    );

    // ── past peak trough maximum minimum: a threshold, records ──────────────
    const extremesHeading = 'past bangs when a number rises to its threshold';
    at = await open(
      '.past',
      slug: 'extremes',
      notes: 6,
      heading: extremesHeading,
    );
    final crossings = at('.i', 140, 330);
    await slide(60, 160, 0.9);
    expect(read(at('.f', 260, 160)), greaterThan(50));
    expect(value(crossings), '1', reason: 'once past 50');
    await slide(60, 160, 0.1);
    expect(value(crossings), '1', reason: 'falling sends nothing');
    await slide(60, 160, 0.9);
    expect(value(crossings), '2', reason: 'again after dropping below');
    for (final m in ['5', '3', '9', '1']) {
      await tap(message(m));
    }
    expect((read(at('.f', 60, 540)), read(at('.f', 300, 540))), (9, 1));
    expect((value(at('.i', 150, 540)), value(at('.i', 390, 540))), ('0', '1'));
    await tap(message('4'));
    expect((read(at('.f', 60, 800)), read(at('.f', 200, 800))), (6, 4));
    await tap(buttonAt(390, 630));
    expect((read(at('.f', 60, 800)), read(at('.f', 200, 800))), (17, 2));
    await close();
    await openRest(
      ['.peak', '.trough', '.maximum', '.minimum'],
      slug: 'extremes',
      notes: 6,
      heading: extremesHeading,
    );

    // ── mean histo anal: an average, a histogram, a Markov chain ────────────
    const statsHeading = 'mean sends the average of every number so far';
    at = await open(
      '.mean',
      slug: 'statistics',
      notes: 5,
      heading: statsHeading,
    );
    for (final m in ['2', '4', '9']) {
      await tap(message(m));
    }
    expect((read(at('.f', 60, 270)), value(at('.i', 150, 270))), (5, '3'));
    final histo = at('.l', 60, 470);
    for (final (m, want) in [
      ('1', '1 1'),
      ('3', '3 1'),
      ('3', '3 2'),
      ('6', '6 1'),
    ]) {
      await tap(message(m));
      expect(value(histo), want);
    }
    await tap(message('12'));
    expect(value(at('.i', 200, 520)), '1', reason: '12 is rejected');
    expect(value(histo), '6 1', reason: 'and not counted');
    for (final m in ['60', '62', '60', '62', '64']) {
      await tap(message(m));
    }
    expect(value(at('.l', 60, 670)), '62 64 1', reason: 'the last pair');
    await tap(buttonAt(390, 620));
    expect(value(at('.i', 300, 730)), '62', reason: 'only 62 followed 60');
    await tap(buttonAt(390, 620));
    expect(['60', '64'], contains(value(at('.i', 300, 730))));
    await close();
    await openRest(
      ['.histo', '.anal'],
      slug: 'statistics',
      notes: 5,
      heading: statsHeading,
    );

    // ── slide linedrive: smoothing, jitter, a curve into line ───────────────
    const slideHeading = 'slide moves its output part of the way';
    at = await open(
      '.slide',
      slug: 'slide-linedrive',
      notes: 6,
      heading: slideHeading,
    );
    final smooth = at('.f', 60, 270);
    await tap(message('100'));
    expect(read(smooth), closeTo(33.333, 1e-3), reason: 'a third');
    await tap(buttonAt(280, 160));
    expect(read(smooth), closeTo(55.556, 1e-3), reason: 'closing in');
    await tap(message('0'));
    expect(read(smooth), closeTo(55.556 * 11 / 12, 1e-3), reason: 'a 12th');
    await tap(toggleAt(60, 350));
    final raw = <double>{};
    final calm = <double>{};
    for (var i = 0; i < 10; i++) {
      await wait(100);
      raw.add(read(at('.f', 200, 450)));
      calm.add(read(at('.f', 60, 560)));
    }
    await tap(toggleAt(60, 350));
    expect(raw.length, greaterThan(2), reason: 'random jumps about');
    expect(calm.length, greaterThan(2), reason: 'slide follows it');
    for (final v in [...raw, ...calm]) {
      expect(v, inInclusiveRange(0, 99));
    }
    expect(loudness(), lessThan(1e-4), reason: 'silent until switched on');
    await slide(60, 650, 1);
    final top = read(at('.f', 140, 760));
    expect(top, closeTo(2000, 30), reason: 'the top');
    // line glides on the audio clock: render, and watch it arrive.
    final glide = at('.f', 140, 930);
    loudness(400);
    expect(read(glide), closeTo(top, 1e-3), reason: 'line arrives');
    await slide(60, 650, 0.5);
    final target = read(at('.f', 140, 760));
    expect(target, closeTo(49, 15), reason: 'about 49 halfway');
    final path = <double>[];
    for (var i = 0; i < 40; i++) {
      loudness(10);
      path.add(read(glide));
    }
    expect(path.last, closeTo(target, 1e-3), reason: 'line arrives again');
    expect(
      path.where((v) => v > target + 1 && v < top - 10),
      isNotEmpty,
      reason: 'it glides on the way',
    );
    await tap(toggleAt(300, 880));
    expect(loudness(), greaterThan(0.05), reason: 'the sine on master');
    await tap(toggleAt(300, 880));
    await close();
    await openRest(
      ['.linedrive'],
      slug: 'slide-linedrive',
      notes: 6,
      heading: slideHeading,
    );

    // ── div swap pong: whole parts, a crossed pair, fold wrap clip ──────────
    const divHeading = 'div divides and keeps the whole part';
    at = await open(
      '.div',
      slug: 'div-swap-pong',
      notes: 4,
      heading: divHeading,
    );
    await tap(message('17'));
    expect((value(at('.i', 60, 270)), value(at('.i', 170, 270))), ('3', '2'));
    await tap(message('-17'));
    expect((value(at('.i', 60, 270)), value(at('.i', 170, 270))), ('-3', '-2'));
    await tap(message('7'));
    await tap(message('3'));
    expect(numbers(at('.l', 60, 570)), [7, 3], reason: 'crossed');
    await tap(message('13'));
    expect(
      [
        for (final x in [60.0, 200.0, 340.0]) read(at('.f', x, 810)),
      ],
      [7, 3, 10],
    );
    await close();
    await openRest(
      ['.swap', '.pong'],
      slug: 'div-swap-pong',
      notes: 4,
      heading: divHeading,
    );

    // ── cartopol poltocar: the pad in polar form, back, and a circle ────────
    const polarHeading = 'cartopol turns a point x y into polar form';
    at = await open(
      '.cartopol',
      slug: 'cartopol-poltocar',
      notes: 5,
      heading: polarHeading,
    );
    final pad = tester.getRect(find.byType(PatchXyPad));
    await tester.dragFrom(
      pad.center,
      Offset(pad.width / 2 - 4, -(pad.height / 2 - 4)),
    );
    await tester.pumpAndSettle();
    var x = read(at('.f', 60, 320));
    var y = read(at('.f', 150, 320));
    expect(x, greaterThan(0.8), reason: 'right');
    expect(y, greaterThan(0.8), reason: 'top');
    expect(read(at('.f', 60, 430)), closeTo(math.sqrt(x * x + y * y), 1e-4));
    expect(read(at('.f', 170, 430)), closeTo(math.atan2(y, x), 1e-4));
    expect(read(at('.f', 170, 540)), inExclusiveRange(30, 60), reason: 'deg');
    expect(read(at('.f', 60, 650)), closeTo(x, 1e-4), reason: 'x back');
    expect(read(at('.f', 170, 650)), closeTo(y, 1e-4), reason: 'y back');
    await tester.dragFrom(pad.center, Offset(-(pad.width / 2 - 4), 0));
    await tester.pumpAndSettle();
    expect(read(at('.f', 170, 540)).abs(), greaterThan(170), reason: 'left');
    await tap(toggleAt(330, 160));
    final angles = <double>{};
    for (var i = 0; i < 8; i++) {
      await wait(100);
      expect(read(at('.f', 60, 430)), closeTo(0.8, 1e-3), reason: 'circle');
      angles.add(read(at('.f', 170, 430)));
      x = read(at('.f', 60, 320));
      y = read(at('.f', 150, 320));
      expect(math.sqrt(x * x + y * y), closeTo(0.8, 1e-3), reason: 'pad');
    }
    expect(angles.length, greaterThan(2), reason: 'it goes round');
    await tap(toggleAt(330, 160));
    await close();
    await openRest(
      ['.poltocar'],
      slug: 'cartopol-poltocar',
      notes: 5,
      heading: polarHeading,
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
