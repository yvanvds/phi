import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_bang_square.dart';
import 'package:phi/design/widgets/patcher/patch_keyboard.dart';
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

/// End-to-end proof of the **control math tutorials** (issue #495) through
/// the real [PhiApp]: real rail navigation, fonts and layout, the real asset
/// bundle and the real patcher engine ([RealPatcherGateway] on an offline
/// libyse session). Only the audio device and MIDI are fakes.
///
/// The arithmetic, comparison, logic, range, math function, expression and
/// pitch/level conversion tutorials are opened from the palette's Tutorials
/// tab, once through each type they cover. The test checks that the notes
/// render and nothing overlaps, then plays the patches with real taps and
/// drags and reads the results back from the engine, the way the notes tell
/// the user to. The two audible ones are heard on the master meter.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Finder message(String text) => find.descendant(
    of: find.byType(PatchMessageBox),
    matching: find.text(text),
  );

  testWidgets('patcher: every control math tutorial opens from the Tutorials '
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
          newLocationPath: '/projects/control-math.phi',
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
      if (tutorial.mounted) {
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

    // Every widget [f] finds, top to bottom on the canvas, or left to right
    // with [across].
    List<Finder> inOrder(Finder f, {bool across = false}) {
      double key(Finder e) =>
          across ? tester.getTopLeft(e).dx : tester.getTopLeft(e).dy;
      return [for (var i = 0; i < f.evaluate().length; i++) f.at(i)]
        ..sort((a, b) => key(a).compareTo(key(b)));
    }

    // The numbers in a list box.
    List<double> numbers(int id) => [
      for (final t in value(id).split(' ')) double.parse(t),
    ];

    // A tap at [at], with time for the body's poll.
    Future<void> tapAt(Offset at) async {
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    // The numbers a row of result boxes shows, left to right.
    List<double> row(
      int Function(String, double, double) at,
      String type,
      double y,
      List<double> xs,
    ) => [for (final x in xs) read(at(type, x, y))];

    const six = [60.0, 150.0, 240.0, 330.0, 420.0, 510.0];

    // ── + - * / % !- !/: hot and cold, trigger b f, the rest ────────────────
    var at = await open(
      '.+',
      slug: 'arithmetic',
      notes: 5,
      heading: 'Each takes two numbers. The left inlet is hot',
    );
    expect(library.tutorial!.mounted, isFalse, reason: 'nothing to hear');
    await tap(message('3'));
    expect(read(at('.f', 60, 270)), 13, reason: '3 + the argument 10');
    await tap(message('100'));
    expect(read(at('.f', 60, 270)), 13, reason: 'the right inlet is cold');
    await tap(message('7'));
    expect(read(at('.f', 60, 270)), 107);
    await tap(message('2'));
    await tap(message('5'));
    expect(read(at('.f', 60, 550)), 7, reason: 'trigger b f');
    await tap(message('8'));
    expect(read(at('.f', 60, 550)), 10, reason: 'the right side is hot too');
    await tap(message('10'));
    final ops = row(at, '.f', 790, six);
    expect(ops.sublist(0, 4), [6, 40, 2.5, 2]);
    expect(ops[4], -6);
    expect(ops[5], closeTo(0.4, 1e-6));
    await tap(message('-7'));
    expect(read(at('.f', 330, 790)), -3, reason: '% keeps the sign');
    await tap(message('0'));
    await tap(message('10'));
    expect(row(at, '.f', 790, six), [10, 0, 0, 0, -10, 0], reason: 'by 0');
    await close();
    for (final type in ['.-', '.*', './', '.%', '.!-', '.!/']) {
      await open(
        type,
        slug: 'arithmetic',
        notes: 5,
        heading: 'Each takes two numbers',
      );
      await close();
    }

    // ── == != < <= > >=: six answers, a threshold, a gate ───────────────────
    at = await open(
      '.==',
      slug: 'comparison',
      notes: 5,
      heading: 'Each compares the left operand',
    );
    await tap(message('5'));
    expect(row(at, '.i', 330, six), [1, 0, 0, 1, 0, 1]);
    await tap(message('5.5'));
    expect(row(at, '.i', 330, six), [0, 1, 0, 0, 1, 1]);
    final state = at('.i', 60, 630);
    final passed = at('.i', 330, 750);
    await tap(message('42'));
    expect(value(passed), '0', reason: 'the gate starts closed');
    await slide(60, 410, 0.9);
    expect(read(at('.f', 140, 410)), greaterThan(0.5));
    expect(value(state), '1', reason: 'above the threshold');
    await tap(message('42'));
    expect(value(passed), '42', reason: 'the comparison opened the gate');
    await slide(60, 410, 0.1);
    expect(value(state), '0');
    await close();
    for (final type in ['.!=', '.<', '.<=', '.>', '.>=']) {
      await open(
        type,
        slug: 'comparison',
        notes: 5,
        heading: 'Each compares the left operand',
      );
      await close();
    }

    // ── && || & | << >>: two toggles, bits, shifts, packing ─────────────────
    at = await open(
      '.&&',
      slug: 'logic',
      notes: 6,
      heading: 'are logical: any number other than 0',
    );
    await tap(toggleAt(60, 160));
    expect((value(at('.i', 60, 320)), value(at('.i', 170, 320))), ('0', '1'));
    await tap(toggleAt(200, 160));
    expect((value(at('.i', 60, 320)), value(at('.i', 170, 320))), ('1', '1'));
    await tap(toggleAt(60, 160));
    expect((value(at('.i', 60, 320)), value(at('.i', 170, 320))), ('0', '1'));
    await tap(message('12'));
    expect((value(at('.i', 60, 500)), value(at('.i', 170, 500))), ('8', '14'));
    await tap(message('-8'));
    expect(
      (value(at('.i', 300, 500)), value(at('.i', 410, 500))),
      ('-16', '-4'),
    );
    await tap(message('2'));
    await tap(message('5'));
    expect(value(at('.i', 60, 790)), '37', reason: '2 × 16 + 5');
    expect((value(at('.i', 60, 900)), value(at('.i', 200, 900))), ('2', '5'));
    await close();
    for (final type in ['.||', '.&', '.|', '.<<', '.>>']) {
      await open(
        type,
        slug: 'logic',
        notes: 6,
        heading: 'are logical: any number other than 0',
      );
      await close();
    }

    // ── abs round clip scale zmap: a grid, limits, ranges, a curve ──────────
    at = await open(
      '.scale',
      slug: 'range',
      notes: 5,
      heading: 'abs drops the sign, round snaps',
    );
    await tap(message('-3.5'));
    expect(row(at, '.f', 330, [60, 170, 300]), [3.5, -3.5, 0]);
    await tap(message('0.37'));
    expect(row(at, '.f', 330, [60, 170, 300]), [
      closeTo(0.37, 1e-6),
      0.25,
      closeTo(0.37, 1e-6),
    ]);
    await tap(message('0.5'));
    await tap(message('0.37'));
    expect(read(at('.f', 170, 330)), 0.5, reason: 'a grid of halves');
    await tap(message('150'));
    expect(read(at('.f', 300, 330)), 100, reason: 'clipped');
    await tap(message('160'));
    expect(read(at('.f', 60, 570)), closeTo(1.26, 0.005), reason: 'scale');
    expect(read(at('.f', 300, 570)), 1, reason: 'zmap stops at the limit');
    await slide(60, 650, 0.5);
    final linear = read(at('.f', 140, 700));
    final curved = read(at('.f', 140, 810));
    expect(linear, inExclusiveRange(1200, 2100), reason: 'about halfway');
    expect(curved, lessThan(0.7 * linear), reason: 'the curve stays low');
    await close();
    for (final type in ['.abs', '.round', '.clip', '.zmap']) {
      await open(
        type,
        slug: 'range',
        notes: 5,
        heading: 'abs drops the sign, round snaps',
      );
      await close();
    }

    // ── sin cos tan … pow sqrt: twelve answers, an LFO, atan2 ───────────────
    at = await open(
      '.sin',
      slug: 'math-functions',
      notes: 6,
      heading: 'sin, cos and tan take an angle in radians',
    );
    expect(library.tutorial!.mounted, isTrue, reason: 'the LFO is audible');
    expect(loudness(), lessThan(1e-4), reason: 'silent until switched on');
    await tap(message('0.5'));
    expect(read(at('.f', 60, 330)), closeTo(0.479426, 1e-5), reason: 'sin');
    await tap(message('2.'));
    expect(read(at('.f', 330, 330)), 0, reason: 'asin of 2 has no value');
    expect(read(at('.f', 240, 440)), closeTo(0.964028, 1e-5), reason: 'tanh');
    await tap(message('-3'));
    expect(read(at('.f', 420, 440)), 0, reason: 'acosh below 1');
    // The LFO: metro runs in real time, so give it real time to step.
    await tap(toggleAt(60, 520));
    final hz = at('.f', 60, 890);
    final seen = <double>{};
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pump();
      seen.add(read(hz));
    }
    expect(seen.length, greaterThan(2), reason: 'the frequency glides');
    for (final f in seen) {
      expect(f, inInclusiveRange(300, 600));
    }
    expect(loudness(), greaterThan(0.02), reason: 'the sine on master');
    await slide(330, 520, 0.5);
    final s = read(at('.slider', 330, 520));
    expect(read(at('.f', 420, 570)), closeTo(s * s * s, 1e-4), reason: 'pow');
    expect(read(at('.f', 520, 570)), closeTo(math.sqrt(s), 1e-4));
    await tap(message('1.'));
    expect(read(at('.f', 330, 1050)), closeTo(90, 1e-3), reason: 'straight up');
    await tap(message('-1.'));
    expect(read(at('.f', 330, 1050)), closeTo(135, 1e-3));
    await tap(toggleAt(60, 520));
    await close();
    for (final type in [
      '.cos',
      '.tan',
      '.asin',
      '.acos',
      '.atan',
      '.atan2',
      '.sinh',
      '.cosh',
      '.tanh',
      '.asinh',
      '.acosh',
      '.atanh',
      '.pow',
      '.sqrt',
    ]) {
      await open(
        type,
        slug: 'math-functions',
        notes: 6,
        heading: 'sin, cos and tan take an angle in radians',
      );
      await close();
    }

    // ── expr vexpr: two inlets, int against float, a list, element-wise ─────
    at = await open(
      '.expr',
      slug: 'expr',
      notes: 5,
      heading: 'expr works out a C-style expression',
    );
    await tap(message('1'));
    expect(read(at('.f', 60, 270)), 0, reason: 'the right inlet only stores');
    await tap(message('3'));
    expect(read(at('.f', 60, 270)), 7);
    await tap(message('7'));
    expect((read(at('.f', 60, 450)), read(at('.f', 250, 450))), (3, 3.5));
    final buttons = inOrder(find.byType(PatchBangSquare));
    await tap(buttons.first);
    expect(read(at('.f', 60, 680)), 5, reason: 'the list 3 4');
    await close();
    at = await open(
      '.vexpr',
      slug: 'expr',
      notes: 5,
      heading: 'expr works out a C-style expression',
    );
    final list = at('.l', 60, 920);
    final bottom = inOrder(find.byType(PatchBangSquare)).sublist(1);
    bottom.sort(
      (a, b) => tester.getTopLeft(a).dx.compareTo(tester.getTopLeft(b).dx),
    );
    await tap(bottom.last); // 10 20 30
    await tap(bottom.first); // 1 2 3
    expect(numbers(list), [10, 40, 90]);
    await tap(message('2'));
    await tap(bottom.first);
    expect(numbers(list), [2, 4, 6], reason: 'one number for every item');
    await close();

    // ── mtof ftom dbtoa atodb: a keyboard, a decibel fader, back again ──────
    at = await open(
      '.mtof',
      slug: 'conversions',
      notes: 5,
      heading: 'mtof turns a MIDI note number into a frequency',
    );
    expect(library.tutorial!.mounted, isTrue);
    expect(loudness(), lessThan(1e-4), reason: 'the fader starts down');
    await slide(400, 160, 1);
    expect(read(at('.f', 400, 380)), closeTo(100, 1), reason: 'dB');
    expect(read(at('.f', 400, 480)), closeTo(1, 0.05), reason: 'amplitude');
    final loud = loudness();
    expect(loud, greaterThan(0.1), reason: 'the sine on master');
    await slide(400, 160, 0.5);
    expect(read(at('.f', 400, 380)), closeTo(80, 3));
    expect(
      loudness(),
      inExclusiveRange(0.03 * loud, 0.3 * loud),
      reason: '-20 dB',
    );
    PatchKeyboard keyboard() =>
        tester.widget<PatchKeyboard>(find.byType(PatchKeyboard));
    Offset keyAt(int pitch) {
      final box = tester.getRect(find.byType(PatchKeyboard));
      final b = keyboard().layout.boundsOf(pitch);
      return box.topLeft +
          Offset(box.width * (b.left + b.right) / 2, box.height * 0.85);
    }

    await tapAt(keyAt(69));
    expect(read(at('.f', 60, 310)), closeTo(440, 1e-3), reason: 'key 69');
    await tapAt(keyAt(81));
    expect(read(at('.f', 60, 310)), closeTo(880, 1e-3), reason: 'an octave');
    await tap(message('440.'));
    expect(read(at('.f', 60, 750)), closeTo(69, 1e-4));
    await tap(message('452.89'));
    expect(read(at('.f', 60, 750)), closeTo(69.5, 1e-3));
    await tap(message('0.'));
    expect(read(at('.f', 60, 750)), -1500, reason: 'finite');
    await tap(message('0.5'));
    expect(read(at('.f', 60, 940)), closeTo(93.98, 0.01));
    expect(read(at('.f', 60, 1050)), closeTo(-6.02, 0.01), reason: 'dBFS');
    await close();
    for (final type in ['.ftom', '.atodb', '.dbtoa']) {
      await open(
        type,
        slug: 'conversions',
        notes: 5,
        heading: 'mtof turns a MIDI note number into a frequency',
      );
      await close();
    }

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
