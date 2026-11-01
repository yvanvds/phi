import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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

/// End-to-end proof of the **control flow and ordering tutorials** (issue
/// #499) through the real [PhiApp]: real rail navigation, fonts and
/// layout, the real asset bundle and the real patcher engine
/// ([RealPatcherGateway] on an offline libyse session). Only the audio device
/// and MIDI are fakes.
///
/// The trigger, bangbang, uzi, if, loadbang-loadmess, onebang, buddy-bondo
/// and next-match tutorials are opened from the palette's Tutorials tab by
/// searching for one of their types. The test checks that the notes render and
/// nothing overlaps, then plays the patches with real taps, typing and a
/// slider drag and reads the results back from the canvas and the engine, the
/// way the notes tell the user to. The loadbang tutorial is heard on the
/// master meter, and its metro, set going on open, ticks in real time.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Finder message(String text) => find.descendant(
    of: find.byType(PatchMessageBox),
    matching: find.text(text),
  );

  testWidgets('patcher: every control flow and ordering tutorial opens '
      'from the Tutorials tab and does what its notes say', (tester) async {
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
          newLocationPath: '/projects/control-flow-tutorials.phi',
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
      expect(field, findsOneWidget, reason: '$type at ($x, $y)');
      // enterText asks for the keyboard only the first time it types into a
      // field (the binding remembers it as focusedEditable): click the box,
      // and forget the remembered field so typing into it twice works (#527).
      await tester.tap(field);
      await tester.pumpAndSettle();
      tester.binding.focusedEditable = null;
      await tester.enterText(field, text);
      expect(
        tester.widget<TextField>(field).focusNode!.hasFocus,
        isTrue,
        reason: 'the click focused $type at ($x, $y)',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    // Whether a list box on the canvas shows [text], once the live-value poll
    // has come due.
    Future<bool> listShows(String text) async {
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      return find
          .descendant(of: find.byType(PatchListBox), matching: find.text(text))
          .evaluate()
          .isNotEmpty;
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

    // ── trigger: conversions, right to left, broken vs fixed ────────────────
    var at = await open(
      '.trigger',
      slug: 'trigger',
      notes: 6,
      heading: 'each outlet converts it by its argument',
    );
    await typeInto('.f', 60, 160, '2.7');
    expect(value(at('.i', 60, 380)), '1', reason: 'b bangs the counter');
    expect(value(at('.i', 160, 380)), '2', reason: 'i truncates');
    expect(read(at('.f', 250, 380)), closeTo(2.7, 1e-6), reason: 'f keeps');
    expect(await shown('.i', 460, 380), 7, reason: 'the constant on screen');
    await tap(buttonAt(180, 160));
    expect(value(at('.l', 340, 380)), '5 6', reason: 'l passes a list');
    expect(value(at('.i', 160, 380)), '0', reason: 'i reads no list');
    await tap(buttonAt(480, 160));
    expect(await listShows('3 2 1'), isTrue, reason: 'right to left');
    await typeInto('.i', 60, 480, '5');
    expect((value(at('.i', 60, 610)), value(at('.i', 240, 670))), ('5', '10'));
    await typeInto('.i', 60, 480, '7');
    expect(
      (value(at('.i', 60, 610)), value(at('.i', 240, 670))),
      ('12', '14'),
      reason: 'the fan-out adds the old number; trigger i i doubles',
    );
    expect(await shown('.i', 240, 670), 14, reason: 'on screen');
    await close();

    // ── bangbang: right to left, store then fire ────────────────────────────
    at = await open(
      '.bangbang',
      slug: 'bangbang',
      notes: 5,
      heading: 'Its argument is the number of outlets',
    );
    await tap(buttonAt(60, 160));
    expect(await listShows('3 2 1'), isTrue, reason: 'right to left');
    for (var n = 1; n <= 3; n++) {
      await tap(buttonAt(60, 480));
      expect(value(at('.i', 60, 650)), '$n');
      expect(value(at('.i', 60, 770)), '${n * 10}', reason: 'stored, fired');
    }
    expect(await shown('.i', 60, 770), 30, reason: 'on screen');
    await close();

    // ── uzi: a loop, the count, a table in one click ────────────────────────
    at = await open(
      '.uzi',
      slug: 'uzi',
      notes: 6,
      heading: 'sends a burst of bangs at once',
    );
    await tap(buttonAt(60, 160));
    expect(
      (value(at('.i', 60, 330)), value(at('.i', 200, 330))),
      ('4', '1'),
      reason: 'four bangs and a carry',
    );
    expect(await shown('.i', 340, 330), 4, reason: 'the last index');
    await tap(message('5'));
    expect(value(at('.i', 60, 330)), '9');
    await tap(message('2'));
    await tap(buttonAt(60, 160));
    expect(value(at('.i', 60, 330)), '11', reason: 'a run of two');
    await tap(buttonAt(60, 430));
    await typeInto('.i', 420, 650, '3');
    expect(await shown('.i', 60, 770), 36, reason: 'address 3 holds 36');
    await tap(message('sum'));
    expect(value(at('.i', 60, 770)), '336');
    await tap(message('clear'));
    await tap(message('sum'));
    expect(value(at('.i', 60, 770)), '0');
    await close();

    // ── if: then and else, two inlets, a filter ─────────────────────────────
    at = await open(
      '.if',
      slug: 'if',
      notes: 5,
      heading: 'tests a condition and sends one message',
    );
    await slide(60, 160, 0.9);
    expect(whole(at('.i', 60, 320)), greaterThan(64));
    final loud = whole(at('.i', 60, 490));
    expect(loud, greaterThan(0), reason: 'then bang');
    await slide(60, 160, 0.2);
    final low = whole(at('.i', 360, 440));
    expect(low, inInclusiveRange(1, 64), reason: 'else out2 \$i1');
    expect(low, whole(at('.i', 60, 320)));
    await typeInto('.i', 200, 580, '30');
    expect(value(at('.i', 60, 700)), '0', reason: 'the right inlet stores');
    await typeInto('.i', 60, 580, '20');
    expect(await shown('.i', 60, 700), 30, reason: 'the larger');
    await typeInto('.i', 400, 580, '3');
    expect(value(at('.i', 400, 700)), '0', reason: 'odd: nothing');
    await typeInto('.i', 400, 580, '4');
    expect(value(at('.i', 400, 700)), '4');
    await close();

    // ── loadbang and loadmess: a gain and a metro on open ───────────────────
    at = await open(
      '.loadbang',
      slug: 'loadbang-loadmess',
      notes: 6,
      heading: 'once the patch has opened',
    );
    expect(read(at('.f', 60, 220)), closeTo(0.1, 1e-6), reason: 'loadmess');
    final level = loudness();
    expect(level, greaterThan(0.05), reason: 'the sine on master');
    expect(value(at('.t', 60, 500)), 'on', reason: 'loadbang');
    final ticks = whole(at('.i', 60, 720));
    await wait(1200);
    expect(whole(at('.i', 60, 720)), greaterThanOrEqualTo(ticks + 2));
    await tap(toggleAt(60, 500));
    expect(value(at('.t', 60, 500)), 'off');
    await tap(message('0'));
    expect(loudness(), 0, reason: 'silenced');
    await tap(buttonAt(300, 560));
    expect(read(at('.f', 60, 220)), closeTo(0.1, 1e-6), reason: 'again');
    await tap(message('0.02'));
    expect(read(at('.f', 60, 220)), closeTo(0.1, 1e-6), reason: 'set only');
    await tap(buttonAt(300, 560));
    expect(read(at('.f', 60, 220)), closeTo(0.02, 1e-6));
    expect(loudness(), closeTo(level / 5, 0.01), reason: 'a fifth as loud');
    await tap(message('0'));
    await close();

    // ── onebang: once, until armed again ────────────────────────────────────
    at = await open(
      '.onebang',
      slug: 'onebang',
      notes: 5,
      heading: 'lets one message through as a bang',
    );
    for (var i = 0; i < 3; i++) {
      await tap(buttonAt(60, 160));
    }
    expect((value(at('.i', 60, 350)), value(at('.i', 220, 350))), ('1', '2'));
    await tap(buttonAt(400, 160));
    await tap(message('0'));
    expect(value(at('.i', 60, 350)), '2', reason: 'armed again: 0 passes');
    await tap(buttonAt(400, 160));
    await tap(message('stop'));
    await tap(buttonAt(60, 160));
    expect((value(at('.i', 60, 350)), value(at('.i', 220, 350))), ('2', '3'));
    expect(await shown('.i', 220, 350), 3, reason: 'on screen');
    await close();

    // ── buddy and bondo: wait for all, or send on any change ────────────────
    at = await open(
      '.buddy',
      slug: 'buddy-bondo',
      notes: 5,
      heading: 'waits until every inlet has a value',
    );
    await typeInto('.i', 200, 160, '60');
    expect(value(at('.i', 340, 380)), '0', reason: 'buddy waits');
    await typeInto('.i', 60, 160, '100');
    expect(
      (value(at('.i', 60, 280)), value(at('.i', 200, 280))),
      ('100', '60'),
    );
    expect(await shown('.i', 340, 380), 1, reason: 'one send');
    await typeInto('.i', 60, 160, '72');
    expect(value(at('.i', 340, 380)), '1', reason: 'empty again');
    await typeInto('.i', 200, 480, '60');
    expect(
      (value(at('.i', 60, 600)), value(at('.i', 200, 600))),
      ('0', '60'),
      reason: 'bondo sends at once',
    );
    await typeInto('.i', 60, 480, '100');
    expect(value(at('.i', 60, 600)), '100');
    await tap(buttonAt(340, 480));
    expect(await shown('.i', 340, 700), 3, reason: 'three sends');
    await close();

    // ── next and match: events and a pattern ────────────────────────────────
    at = await open(
      '.next',
      slug: 'next-match',
      notes: 5,
      heading: 'tells the first message of an event',
    );
    await tap(buttonAt(60, 160));
    await tap(message('42'));
    await tap(buttonAt(300, 160));
    expect(
      (value(at('.i', 60, 420)), value(at('.i', 200, 420))),
      ('3', '2'),
      reason: 'one per click; uzi 3 is one event',
    );
    for (final n in ['60', '64', '67']) {
      await tap(message(n));
    }
    expect(await listShows('60 64 67'), isTrue, reason: 'a match');
    await tap(message('60'));
    await tap(message('67'));
    await tap(message('64'));
    expect(value(at('.i', 240, 740)), '1', reason: 'no match');
    await close();

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
