import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_message_box.dart';
import 'package:phi/design/widgets/patcher/patch_note_box.dart';
import 'package:phi/design/widgets/patcher/patch_object_box.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';
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
import 'package:phi/surfaces/patcher/patch_canvas_mode.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:phi/surfaces/patcher/subpatch/subpatch_window_view.dart';
import 'package:phi/surfaces/patcher/tutorial/patch_tutorial_bar.dart';
import 'package:yse/yse.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';
import '../test/surfaces/patcher/test_support/open_tutorial_by_search.dart';
import '../test/surfaces/patcher/test_support/type_into_field.dart';

/// End-to-end proof of the **subpatch tutorial** (issue #536) through the
/// real [PhiApp]: real rail navigation, fonts and layout, the real asset
/// bundle, the real patcher engine ([RealPatcherGateway] on an offline libyse
/// session) and a **second native window** for the subpatch. Only the audio
/// device and MIDI are fakes.
///
/// The tutorial is opened from the palette's Tutorials tab by searching for
/// `patcher`. The test checks the notes and that nothing overlaps, then plays
/// the gain subpatch with real taps and typing and listens on master. It
/// double-clicks the box, as note 2 says, and checks the window that opens:
/// read-only, in run mode, the boundary objects and the note inside laid out
/// without overlaps. A message into the box's audio inlet changes nothing,
/// and the editor's own drag-time check refuses a number box there while it
/// takes a message box (note 4). The four boundary objects find the same
/// tutorial in the browser.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: the subpatch tutorial opens from the Tutorials tab, '
      'plays its gain subpatch on master, and opens it in its own window', (
    tester,
  ) async {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
    addTearDown(System.instance.close);

    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final gateway = RealPatcherGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
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
          newLocationPath: '/projects/subpatch-tutorial.phi',
        ),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();
    // The new project's empty patch stays stopped (#523): master hears only
    // the tutorial.
    expect(gateway.isSourceReady(engine.patcher.instanceId), isFalse);
    await tester.tap(
      find.byKey(PatcherPalette.tabKey(PatcherPaletteTab.tutorials)),
    );
    await tester.pumpAndSettle();

    final library = engine.patchLibrary;

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

    // A mono sine through [gain]: one channel, centred on master, so each
    // side 3 dB down.
    double through(double gain) => gain * math.sqrt1_2;

    Finder mainCanvas() =>
        find.byWidgetPredicate((w) => w is PatcherCanvas && w.scope == null);
    Finder windowCanvas() => find.byKey(SubpatchWindowView.canvasKey);

    // The view of the [type] object placed at ([x], [y]) in [canvas].
    Finder nodeAt(Finder canvas, String type, double x, double y) =>
        find.descendant(
          of: canvas,
          matching: find.byWidgetPredicate(
            (w) =>
                w is PatcherNodeView &&
                w.node.type == type &&
                w.node.position == Offset(x, y),
          ),
        );

    Finder messageAt(double x, double y) => find.descendant(
      of: nodeAt(mainCanvas(), '.m', x, y),
      matching: find.byType(PatchMessageBox),
    );

    Finder numberField(double x, double y) => find.descendant(
      of: nodeAt(mainCanvas(), '.f', x, y),
      matching: find.descendant(
        of: find.byType(NumberNodeBody),
        matching: find.byType(TextField),
      ),
    );

    // What the number box at ([x], [y]) shows, once a few blocks have run and
    // the surface's live-value poll has come due.
    Future<double> shown(double x, double y) async {
      loudness(5);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      final field = numberField(x, y);
      expect(field, findsOneWidget, reason: '.f at ($x, $y)');
      return double.parse(tester.widget<TextField>(field).controller!.text);
    }

    Future<void> tap(Finder f) async {
      expect(f, findsOneWidget, reason: 'tap target: $f');
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    // No note or object in [canvas] overlaps another one, in the real font.
    void expectNoOverlaps(Finder canvas, String where) {
      final views = find.descendant(
        of: canvas,
        matching: find.byType(PatcherNodeView),
      );
      final boxes = [
        for (final e in views.evaluate())
          (
            (e.widget as PatcherNodeView).node,
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
      expect(overlaps, isEmpty, reason: '$where: overlapping nodes');
    }

    // A tutorial is mounted while open (#528). libyse sets the sound up on a
    // worker thread in wall-clock time: render with real pauses until it is
    // in the mix (#525), then let what was ringing before drain away.
    Future<void> untilMounted() async {
      final id = library.tutorial!.instanceId;
      for (var i = 0; i < 5000; i++) {
        if (gateway.isSourceReady(id)) break;
        System.instance
          ..renderOffline(1)
          ..update();
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(gateway.isSourceReady(id), isTrue, reason: 'joined the mix');
      loudness(20);
    }

    // ── Open it from the Tutorials tab ──────────────────────────────────────
    await openTutorialBySearch(tester, 'patcher');
    final tutorial = library.tutorial;
    expect(tutorial, isNotNull);
    expect(tutorial!.slug, 'subpatch');
    expect(find.byKey(PatchTutorialBar.bannerKey), findsOneWidget);
    // The title note and notes 1–4 in the parent; the subpatch's own note is
    // not drawn there.
    expect(
      find.descendant(of: mainCanvas(), matching: find.byType(PatchNoteBox)),
      findsNWidgets(5),
    );
    expect(
      find.textContaining('A patcher box holds a patch', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Inside gain', findRichText: true),
      findsNothing,
    );
    expectNoOverlaps(mainCanvas(), 'parent');

    await untilMounted();

    final editor = tutorial.editor;
    final box = editor.graph.nodes.singleWhere((n) => n.type == Obj.patcher);
    expect(editor.subpatchNameOf(box.id), 'gain');
    // Its pins are the boundary objects inside: audio, then control.
    expect(box.inputs.map((p) => p.kind), [
      PatchPortKind.audio,
      PatchPortKind.control,
    ]);
    expect(box.outputs.map((p) => p.kind), [
      PatchPortKind.audio,
      PatchPortKind.control,
    ]);
    final boxFace = tester.widget<PatchObjectBox>(
      find.descendant(
        of: nodeAt(mainCanvas(), Obj.patcher, 60, 340),
        matching: find.byType(PatchObjectBox),
      ),
    );
    expect(boxFace.inputPortXs, hasLength(2));
    expect(boxFace.outputPortXs, hasLength(2));

    // ── Note 1: the gain sets the level, and comes back out ──────────────────
    expect(loudness(), lessThan(1e-4), reason: 'silent on open: ~* 0');
    await tap(messageAt(350, 160)); // 0.1
    expect(loudness(), closeTo(through(0.1), 1e-3));
    expect(await shown(200, 420), closeTo(0.1, 1e-6));
    await tap(messageAt(460, 160)); // 0.2
    expect(loudness(), closeTo(through(0.2), 1e-3));
    expect(await shown(200, 420), closeTo(0.2, 1e-6));
    await typeIntoField(
      tester,
      numberField(240, 220),
      '0.15',
      what: 'the gain box',
    );
    expect(loudness(), closeTo(through(0.15), 1e-3), reason: 'typed');
    expect(await shown(200, 420), closeTo(0.15, 1e-6));
    await tap(messageAt(240, 160)); // 0.
    loudness(20);
    expect(loudness(), lessThan(1e-4), reason: '0. turns it off');

    // ── Note 2: double-click the box, and it opens in its own window ────────
    final line = find.descendant(
      of: mainCanvas(),
      matching: find.byKey(PatcherNodeView.objectLineKey(box.id)),
    );
    await tester.tap(line);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(line);
    await tester.pumpAndSettle();
    expect(find.byType(SubpatchWindowView), findsOneWidget);
    expect(tester.binding.platformDispatcher.views, hasLength(2));
    expect(
      tester.widget<Text>(find.byKey(SubpatchWindowView.titleKey)).data,
      'gain',
    );
    // Read-only like the tutorial: run mode, with no toggle out of it.
    expect(find.byKey(SubpatchWindowView.modeKey), findsNothing);
    expect(
      tester.widget<PatcherCanvas>(windowCanvas()).mode,
      PatchCanvasMode.run,
    );
    final inside = {
      for (final e
          in find
              .descendant(
                of: windowCanvas(),
                matching: find.byType(PatcherNodeView),
              )
              .evaluate())
        if ((e.widget as PatcherNodeView).node case final PatchNode n
            when n.type != '.text')
          '${n.type} ${editor.argsOf(n.id)}',
    };
    expect(inside, {'~inlet 0', '.inlet 1', '~* 0', '~outlet 0', '.outlet 1'});
    expect(
      find.descendant(of: windowCanvas(), matching: find.byType(PatchNoteBox)),
      findsOneWidget,
    );
    expect(
      find.textContaining('Inside gain', findRichText: true),
      findsOneWidget,
    );
    expectNoOverlaps(windowCanvas(), 'inside gain');

    // ── Note 4: a message into the audio inlet is dropped ───────────────────
    await tap(messageAt(460, 160)); // 0.2
    final up = loudness();
    expect(up, closeTo(through(0.2), 1e-3));
    await tap(messageAt(60, 240)); // 0. into the ~inlet
    loudness(20);
    expect(loudness(), closeTo(up, 1e-4), reason: 'the sine plays on');
    // The editor's drag-time check: a number box cannot be wired to the
    // box's audio inlet, a message box can.
    PatchPortId outOf(double x, double y, String type) => PatchPortId(
      nodeId: editor.graph.nodes
          .singleWhere((n) => n.type == type && n.position == Offset(x, y))
          .id,
      side: PatchPortSide.output,
      index: 0,
    );
    final audioInlet = PatchPortId(
      nodeId: box.id,
      side: PatchPortSide.input,
      index: 0,
    );
    final gainInlet = PatchPortId(
      nodeId: box.id,
      side: PatchPortSide.input,
      index: 1,
    );
    expect(editor.canConnect(outOf(200, 420, '.f'), audioInlet), isFalse);
    expect(editor.canConnect(outOf(200, 420, '.f'), gainInlet), isTrue);
    expect(editor.canConnect(outOf(350, 160, '.m'), audioInlet), isTrue);

    // Closing the tutorial closes its subpatch window.
    await tap(find.byKey(PatchTutorialBar.closeKey));
    expect(find.byType(SubpatchWindowView), findsNothing);
    expect(tester.binding.platformDispatcher.views, hasLength(1));

    // ── The boundary objects find the same tutorial ─────────────────────────
    for (final type in ['.inlet', '.outlet', '~inlet', '~outlet']) {
      await openTutorialBySearch(tester, type);
      expect(library.tutorial?.slug, 'subpatch', reason: type);
      // Opened afresh at gain 0, with the closed one out of the mix: silent.
      await untilMounted();
      expect(loudness(), lessThan(1e-4), reason: '$type: silent on open');
      await tap(find.byKey(PatchTutorialBar.closeKey));
    }

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await engine.dispose();
    project.dispose();
    appSettings.dispose();
    session.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}
