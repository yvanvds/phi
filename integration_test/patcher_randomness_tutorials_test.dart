import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_bang_square.dart';
import 'package:phi/design/widgets/patcher/patch_list_box.dart';
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

/// End-to-end proof of the **randomness tutorials** (issue #501) through the
/// real [PhiApp]: real rail navigation, fonts and layout, the real asset
/// bundle and the real patcher engine ([RealPatcherGateway] on an offline
/// libyse session). Only the audio device and MIDI are fakes.
///
/// The random, drunk, urn, prob and decide tutorials are opened from the
/// palette's Tutorials tab by searching for their type. The test checks that
/// the notes render and nothing overlaps, then plays the patches with real
/// taps on buttons, message boxes and toggles and real typing into number
/// boxes, and reads the results back from the canvas and the engine, the way
/// the notes tell the user to. Random results are checked by their range, and
/// exactly only where a seed makes them replay. Only drunk makes a sound, on
/// master, while its toggle is on.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Finder message(String text) => find.descendant(
    of: find.byType(PatchMessageBox),
    matching: find.text(text),
  );

  testWidgets('patcher: every randomness tutorial opens from the Tutorials '
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
          newLocationPath: '/projects/randomness-tutorials.phi',
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

    // Lets [ms] milliseconds of real time pass: metro keeps wall-clock time,
    // not the offline render's.
    Future<void> wait(int ms) async {
      await tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: ms)),
      );
      await tester.pump();
    }

    // Taps [f] [n] times and reads the box [out] after each tap.
    Future<List<int>> taps(Finder f, int out, int n) async {
      final read = <int>[];
      for (var i = 0; i < n; i++) {
        await tap(f);
        read.add(int.parse(value(out)));
      }
      return read;
    }

    // ── random: 0 to N-1, a die, the range ──────────────────────────────────
    var at = await open(
      '.random',
      slug: 'random',
      notes: 5,
      heading: 'random sends a random integer on each bang',
    );
    final six = await taps(buttonAt(60, 160), at('.i', 60, 290), 30);
    expect(six.every((n) => n >= 0 && n <= 5), isTrue, reason: '$six');
    expect(six.toSet().length, greaterThan(2), reason: 'not one number');
    expect(
      await shown('.i', 170, 340),
      await shown('.i', 60, 290) + 1,
      reason: '+ 1 makes a die',
    );
    await tap(message('2'));
    final coin = await taps(buttonAt(60, 160), at('.i', 60, 290), 20);
    expect(coin.toSet(), {0, 1}, reason: 'a coin, 0 or 1');
    await tap(message('100'));
    final wide = await taps(buttonAt(60, 160), at('.i', 60, 290), 20);
    expect(wide.every((n) => n >= 0 && n <= 99), isTrue);
    expect(wide.any((n) => n > 5), isTrue, reason: 'up to 99 now');
    await close();

    // ── drunk: a walk, a melody, the step size, the seed ────────────────────
    at = await open(
      '.drunk',
      slug: 'drunk',
      notes: 5,
      heading: 'drunk takes a small random step up or down',
    );
    final pos = at('.i', 60, 350);
    var prev = 0;
    for (final p in await taps(buttonAt(170, 160), pos, 15)) {
      expect(p, inInclusiveRange(0, 24));
      expect((p - prev).abs(), lessThanOrEqualTo(2), reason: 'a small step');
      prev = p;
    }
    await tap(message('12'));
    expect(await shown('.i', 60, 350), 12, reason: 'moved there');
    expect(loudness(), 0, reason: 'silent until the toggle');
    await tap(toggleAt(60, 160));
    expect(loudness(), greaterThan(0.05), reason: 'the melody on master');
    await wait(600);
    loudness(20);
    await tap(toggleAt(60, 160));
    loudness(20);
    expect(loudness(), 0, reason: 'off again');
    await tap(message('-2'));
    await tap(message('12'));
    prev = 12;
    for (final p in await taps(buttonAt(170, 160), pos, 10)) {
      expect((p - prev).abs(), 1, reason: 'never a step of 0');
      prev = p;
    }
    await tap(message('3'));
    await typeInto('.i', 390, 160, '5');
    await tap(message('12'));
    final walk = await taps(buttonAt(170, 160), pos, 8);
    await typeInto('.i', 390, 160, '5');
    await tap(message('12'));
    expect(
      await taps(buttonAt(170, 160), pos, 8),
      walk,
      reason: 'seed 5 again: the same steps',
    );
    await close();

    // ── urn: each once, the empty bang, clear, refilling itself ─────────────
    at = await open(
      '.urn',
      slug: 'urn',
      notes: 5,
      heading: 'urn deals random numbers without repeats',
    );
    final dealt = at('.i', 60, 350);
    final round = await taps(buttonAt(60, 160), dealt, 6);
    expect(round.toSet(), {0, 1, 2, 3, 4, 5}, reason: 'each once');
    await tap(buttonAt(60, 160));
    expect(await shown('.i', 200, 400), 1, reason: 'empty: the right outlet');
    expect(value(dealt), '${round.last}', reason: 'nothing new');
    final clear = find.descendant(
      of: nodeAt('.m', 170, 160),
      matching: find.byType(PatchMessageBox),
    );
    await tap(clear);
    expect((await taps(buttonAt(60, 160), dealt, 6)).toSet(), {
      0,
      1,
      2,
      3,
      4,
      5,
    }, reason: 'all back');
    await tap(toggleAt(340, 290));
    final forever = await taps(buttonAt(60, 160), dealt, 14);
    expect(forever.sublist(1, 7).toSet(), {
      0,
      1,
      2,
      3,
      4,
      5,
    }, reason: 'refilled');
    expect(forever.sublist(8, 14).toSet(), {0, 1, 2, 3, 4, 5});
    await tap(toggleAt(340, 290));
    await close();

    // ── prob: a weighted chain, dump, a new transition, a dead end ──────────
    at = await open(
      '.prob',
      slug: 'prob',
      notes: 6,
      heading: 'prob jumps from state to state',
    );
    final state = at('.i', 60, 410);
    var from = 0;
    const ways = {(0, 1), (0, 2), (1, 0), (1, 2), (2, 0)};
    for (final to in await taps(buttonAt(60, 160), state, 20)) {
      expect(ways, contains((from, to)), reason: 'a stored way out');
      from = to;
    }
    await tap(message('dump'));
    expect(await listShows('2 0 1'), isTrue, reason: 'the last one');
    await typeInto('.i', 280, 560, '4');
    await typeInto('.i', 170, 560, '2');
    await typeInto('.i', 60, 560, '0');
    expect(await listShows('0 2 4'), isTrue, reason: 'pack sent 0 2 4');
    await tap(message('3'));
    await tap(buttonAt(60, 160));
    expect(await shown('.i', 170, 460), 1, reason: 'a dead end');
    await tap(buttonAt(60, 160));
    expect(
      await shown('.i', 60, 410),
      anyOf(1, 2),
      reason: 'back at 0, and on from there',
    );
    await close();

    // ── decide: a coin flip into a gate ─────────────────────────────────────
    at = await open(
      '.decide',
      slug: 'decide',
      notes: 5,
      heading: 'decide sends 0 or 1 on each bang',
    );
    final flip = at('.i', 340, 350);
    final flips = await taps(buttonAt(170, 160), flip, 20);
    expect(flips.every((f) => f == 0 || f == 1), isTrue);
    expect(
      (await shown('.i', 60, 630), await shown('.i', 200, 630)),
      (
        flips.where((f) => f == 0).length.toDouble(),
        flips.where((f) => f == 1).length.toDouble(),
      ),
      reason: '0 goes left, 1 right',
    );
    await typeInto('.i', 280, 160, '7');
    final seeded = await taps(buttonAt(170, 160), flip, 10);
    await typeInto('.i', 280, 160, '7');
    expect(
      await taps(buttonAt(170, 160), flip, 10),
      seeded,
      reason: 'seed 7 again: the same flips',
    );
    int count() =>
        int.parse(value(at('.i', 60, 630))) +
        int.parse(value(at('.i', 200, 630)));
    final before = count();
    await tap(toggleAt(60, 160));
    await wait(700);
    await tap(toggleAt(60, 160));
    expect(count() - before, greaterThanOrEqualTo(2), reason: 'the metro');
    await close();

    expect(loudness(), 0, reason: 'silent once every tutorial is closed');
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
