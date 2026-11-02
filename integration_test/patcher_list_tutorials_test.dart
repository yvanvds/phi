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
import '../test/surfaces/patcher/test_support/open_tutorial_by_search.dart';

/// End-to-end proof of the **list tutorials** (issue #502) through the real
/// [PhiApp]: real rail navigation, fonts and layout, the real asset bundle
/// and the real patcher engine ([RealPatcherGateway] on an offline libyse
/// session). Only the audio device and MIDI are fakes.
///
/// The pack-pak, unpack, iter, join-unjoin, append-prepend, zl and
/// listfunnel-substitute tutorials are opened from the palette's Tutorials
/// tab by searching for one of their types. The test checks that the notes
/// render and nothing overlaps, then plays the patches with real taps on
/// message boxes and buttons and real typing into number boxes, and reads the
/// results back from the canvas and the engine, the way the notes tell the
/// user to. None of them makes a sound, so master stays silent throughout.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Finder message(String text) => find.descendant(
    of: find.byType(PatchMessageBox),
    matching: find.text(text),
  );

  testWidgets('patcher: every list tutorial opens from the Tutorials '
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
          newLocationPath: '/projects/list-tutorials.phi',
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

    // The canvas view of the [type] object placed at ([x], [y]).
    Finder nodeAt(String type, double x, double y) => find.byWidgetPredicate(
      (w) =>
          w is PatcherNodeView &&
          w.node.type == type &&
          w.node.position == Offset(x, y),
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

    // ── pack and pak: typed elements, the hot inlet ─────────────────────────
    var at = await open(
      '.pack',
      slug: 'pack-pak',
      notes: 5,
      heading: 'pack keeps one value per inlet',
    );
    await typeInto('.i', 170, 160, '3');
    await tap(message('bar'));
    expect(value(at('.l', 60, 290)), '', reason: 'the right inlets store');
    await typeInto('.f', 60, 160, '1.7');
    expect(await listShows('1 3. bar'), isTrue, reason: 'typed elements');
    await tap(buttonAt(390, 160));
    expect(value(at('.l', 60, 290)), '1 3. bar');
    await typeInto('.i', 240, 420, '5');
    expect(await listShows('0 5'), isTrue, reason: 'pak sends at once');
    expect(value(at('.l', 60, 540)), '', reason: 'pack only stores');
    expect(await shown('.i', 240, 700), 1);
    await typeInto('.i', 60, 420, '2');
    expect(value(at('.l', 60, 540)), '2 5');
    expect(value(at('.l', 240, 540)), '2 5');
    expect(await shown('.i', 60, 700), 1);
    expect(await shown('.i', 240, 700), 2);
    await close();

    // ── unpack: right to left ───────────────────────────────────────────────
    at = await open(
      '.unpack',
      slug: 'unpack',
      notes: 6,
      heading: 'unpack sends each item of a list out its own outlet',
    );
    await tap(message('foo'));
    expect(await shown('.i', 60, 340), 1, reason: '1.7 cut to 1');
    expect(await shown('.f', 170, 340), 2);
    expect(await listShows('foo'), isTrue);
    await tap(message('6'));
    expect(await shown('.i', 60, 340), 5);
    expect(await shown('.f', 170, 340), 6);
    expect(value(at('.l', 280, 340)), 'foo', reason: 'not reached');
    await tap(buttonAt(340, 160));
    expect(await shown('.i', 60, 340), 5);
    await tap(message('3'));
    expect(await shown('.f', 60, 690), 7, reason: '10 - 3');
    await close();

    // ── iter: one at a time ─────────────────────────────────────────────────
    at = await open(
      '.iter',
      slug: 'iter',
      notes: 5,
      heading: 'iter sends the items of a list one by one',
    );
    await tap(message('67'));
    expect(await shown('.i', 60, 340), 67, reason: 'the last item');
    expect(await shown('.i', 180, 440), 3, reason: 'three items');
    expect(await shown('.f', 300, 390), 79, reason: '+ 12 on each');
    await tap(buttonAt(280, 160));
    expect(await shown('.i', 180, 440), 6, reason: 'the bang repeats');
    await tap(message('5'));
    expect(await shown('.i', 180, 440), 7, reason: 'a list of one');
    await close();

    // ── join and unjoin: whole pieces, chunks ───────────────────────────────
    at = await open(
      '.unjoin',
      slug: 'join-unjoin',
      notes: 6,
      heading: 'join puts the messages held by its inlets end to end',
    );
    await tap(message('4'));
    await tap(message('2'));
    expect(await listShows('1 2 3 4'), isTrue, reason: 'join');
    expect(value(at('.l', 200, 340)), '1 2', reason: 'pack drops the 4');
    await tap(message('5'));
    expect(await listShows('rest 5'), isTrue);
    expect(value(at('.l', 170, 630)), '3 4');
    await tap(message('8'));
    expect(await listShows('6 7'), isTrue);
    expect(await listShows('rest 8'), isTrue);
    expect(value(at('.l', 170, 630)), '3 4', reason: 'no full second group');
    await close();

    // ── append and prepend: before, after, set ──────────────────────────────
    at = await open(
      '.append',
      slug: 'append-prepend',
      notes: 5,
      heading: 'prepend puts its stored message in front',
    );
    await typeInto('.i', 60, 160, '60');
    expect(await listShows('note 60'), isTrue);
    expect(await listShows('note 60 100'), isTrue);
    await tap(message('ctl'));
    await typeInto('.i', 60, 160, '61');
    expect(await listShows('ctl 61 100'), isTrue);
    await tap(message('1'));
    await typeInto('.i', 60, 160, '62');
    expect(await listShows('ctl 62 1'), isTrue);
    await typeInto('.i', 60, 460, '5');
    expect(value(at('.l', 60, 640)), '', reason: 'set 5: kept, not sent');
    expect(await shown('.i', 200, 740), 0);
    await tap(buttonAt(200, 460));
    expect(await listShows('5 0'), isTrue);
    expect(await shown('.i', 200, 740), 1);
    await close();

    // ── zl: modes, the argument, accumulating ───────────────────────────────
    at = await open(
      '.zl',
      slug: 'zl',
      notes: 7,
      heading: 'zl does one of many jobs to a list',
    );
    await tap(message('1'));
    expect(await shown('.i', 200, 380), 4, reason: 'len');
    await tap(message('rev'));
    await tap(buttonAt(400, 160));
    expect(await listShows('1 8 3 5'), isTrue);
    await typeInto('.i', 480, 260, '2');
    await tap(message('nth'));
    await tap(buttonAt(400, 160));
    expect(await shown('.i', 200, 380), 3, reason: 'the second item');
    expect(await listShows('5 8 1'), isTrue, reason: 'the rest');
    await tap(message('rot'));
    await tap(buttonAt(400, 160));
    expect(await listShows('8 1 5 3'), isTrue);
    await tap(message('slice'));
    await tap(buttonAt(400, 160));
    expect(value(at('.l', 60, 380)), '5 3');
    expect(value(at('.l', 330, 380)), '8 1');
    await tap(message('sort'));
    await tap(buttonAt(400, 160));
    expect(await listShows('1 3 5 8'), isTrue);
    await typeInto('.i', 480, 260, '-1');
    await tap(buttonAt(400, 160));
    expect(await listShows('8 5 3 1'), isTrue);
    expect(await listShows('3 1 2 4'), isTrue, reason: 'where each item was');
    for (final n in ['1', '2', '3']) {
      await typeInto('.i', 60, 500, n);
    }
    expect(value(at('.l', 60, 620)), '1 2 3', reason: 'group 3');
    expect(value(at('.l', 240, 620)), '1 2 3', reason: 'stream 3');
    expect(await shown('.i', 400, 620), 0, reason: 'nothing missing');
    await typeInto('.i', 60, 500, '4');
    expect(await listShows('2 3 4'), isTrue, reason: 'the last three');
    await close();

    // ── listfunnel and substitute ───────────────────────────────────────────
    at = await open(
      '.substitute',
      slug: 'listfunnel-substitute',
      notes: 7,
      heading: 'listfunnel sends every item of a list with its index',
    );
    await tap(message('67'));
    expect(await listShows('2 67'), isTrue, reason: 'the last pair');
    expect(await shown('.i', 200, 390), 60);
    expect(await shown('.i', 300, 390), 64);
    expect(await shown('.i', 400, 390), 67);
    await tap(message('60'));
    expect(await listShows('72 64 72'), isTrue);
    expect(await listShows('72 64 60'), isTrue, reason: 'first match only');
    await tap(message('64'));
    expect(await listShows('62 64'), isTrue, reason: 'no match: right');
    await typeInto('.i', 330, 500, '64');
    await tap(message('60'));
    expect(await listShows('60 72 60'), isTrue, reason: '64 is the match');
    await close();

    expect(loudness(), 0, reason: 'nothing here makes a sound');
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
