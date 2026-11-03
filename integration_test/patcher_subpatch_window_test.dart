import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_object_box.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/shell/project/project_menu.dart';
import 'package:phi/surfaces/patcher/create/patch_inline_object_box.dart';
import 'package:phi/surfaces/patcher/patcher_cable_layer.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:phi/surfaces/patcher/patcher_surface.dart';
import 'package:phi/surfaces/patcher/placement/patch_placement_bar.dart';
import 'package:phi/surfaces/patcher/subpatch/subpatch_window_view.dart';
import 'package:yse/yse.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';
import '../test/surfaces/patcher/test_support/embedder_text_input_check.dart';
import '../test/surfaces/patcher/test_support/until_window_active.dart';

/// End-to-end proof of subpatches in their own window (issue #481), through
/// the real [PhiApp] — rail navigation, fonts, layout, a second window from
/// Flutter's windowing API — on the real patcher engine ([RealPatcherGateway]
/// over an offline libyse session). Only the audio device, MIDI, the project
/// store and text input are fakes.
///
/// The second window is flutter_test's **stand-in** for a native one: its
/// binding installs a test windowing owner, and a native window cannot be
/// made under it (its platform dispatcher reports a fake engine id, so the
/// Linux windowing FFI dereferences it and crashes — flutter/flutter#195919).
/// The stand-in view is drawn, hit-tested and focused like a real one, but
/// the engine never hears of it, so the platform's text input plugin is
/// replaced by [EmbedderTextInputCheck].
///
/// The performer types a `patcher gain` box into the patch, opens it from its
/// menu, and builds `~inlet 0` → `~* 0.5` → `~outlet 0` in the window that
/// opens — by keyboard and by dragging cables, as anywhere else. Back in the
/// main window the box has grown the pins those objects define; a sine wired
/// through it to the dac is heard on master. Deleting the `~*` inside silences
/// it; `Ctrl+Z` pressed in the **main** window brings it back (one journal),
/// `Ctrl+Y` takes it away again. Saved and reopened, the patch comes back with
/// its contents and cables, opens again, and sounds again.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: a subpatch built in its own window carries a signal '
      'from its parent, undoes from either window, and survives a save → '
      'reopen', (tester) async {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
    addTearDown(System.instance.close);
    // Text input goes to a stand-in that checks the rule the Windows
    // embedder enforces — a call naming a view must find it alive — instead of
    // to the platform. Under flutter_test a subpatch window is a stand-in view
    // the engine never hears of (see [EmbedderTextInputCheck]), so the real
    // plugin cannot be asked about it.
    final textInput = EmbedderTextInputCheck(tester);
    addTearDown(textInput.dispose);
    await tester.binding.setSurfaceSize(const Size(1600, 1000));

    const dir = '/projects/subpatch.phi';
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    late PhiEngine engine;
    late RealPatcherGateway gateway;

    Future<
      ({
        PhiEngine engine,
        RealPatcherGateway gateway,
        ProjectController project,
        SessionState session,
        AppSettingsController settings,
      })
    >
    launch(String key, {String? newPath}) async {
      final g = RealPatcherGateway();
      final e = PhiEngine(
        FakeYseGateway(),
        patcherGateway: g,
        midiGateway: FakeMidiGateway(),
        telemetryInterval: const Duration(milliseconds: 20),
      );
      final session = SessionState();
      final appSettings = AppSettingsController(settings);
      final project = ProjectController(
        session: session,
        settings: appSettings,
        storeFactory: (_) => store,
        journalStoreFactory: (_) => journal,
        seedRegistry: seedDefaultProject,
        autosaveIntervalOverride: const Duration(hours: 1),
      );
      await tester.pumpWidget(
        PhiApp(
          key: ValueKey(key),
          engine: e,
          session: session,
          projectController: project,
          directoryPicker: FakeProjectDirectoryPicker(newLocationPath: newPath),
          autoStartProject: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(railFor(SurfaceId.patcher));
      await tester.pumpAndSettle();
      engine = e;
      gateway = g;
      return (
        engine: e,
        gateway: g,
        project: project,
        session: session,
        settings: appSettings,
      );
    }

    PatcherController editor() => engine.patcher;

    Finder mainCanvas() =>
        find.byWidgetPredicate((w) => w is PatcherCanvas && w.scope == null);
    Finder windowCanvas() => find.byKey(SubpatchWindowView.canvasKey);

    Finder nodeView(Finder canvas, PatchNodeId id) => find.descendant(
      of: canvas,
      matching: find.byWidgetPredicate(
        (w) => w is PatcherNodeView && w.node.id == id,
      ),
    );

    FlutterView viewOf(Finder f) => tester.viewOf(f);

    // Renders [blocks] blocks offline and returns the loudest master peak.
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

    // libyse sets a new sound up on a worker thread in wall-clock time, while
    // an offline render runs far ahead of it (#525): render with real pauses
    // until the patch is in the mix.
    Future<void> untilMounted() async {
      final id = editor().instanceId;
      for (var i = 0; i < 5000; i++) {
        if (gateway.isSourceReady(id)) break;
        System.instance
          ..renderOffline(1)
          ..update();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(gateway.isSourceReady(id), isTrue, reason: 'joined the mix');
    }

    // Double-clicks the empty grid of [canvas] at [scene], types [line] into
    // the inline object box and presses Enter. Returns the object made.
    Future<PatchNode> create(Finder canvas, Offset scene, String line) async {
      final view = viewOf(canvas);
      final at = tester.getTopLeft(canvas) + scene;
      final before = editor().graph.nodes.map((n) => n.id).toSet();
      final field = find.descendant(
        of: canvas,
        matching: find.byKey(PatchInlineObjectBox.fieldKey),
      );
      for (var attempt = 0; attempt < 3; attempt++) {
        await untilWindowActive(tester);
        if (field.evaluate().isEmpty) {
          await tester.tapAt(at, view: view);
          await tester.pump();
          await tester.tapAt(at, view: view);
          await tester.pumpAndSettle();
        }
        expect(field, findsOneWidget, reason: 'inline box for "$line"');
        tester.binding.focusedEditable = null;
        await tester.enterText(field, line);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        if (editor().graph.nodes.length > before.length) break;
      }
      final made = editor().graph.nodes.where((n) => !before.contains(n.id));
      expect(made, hasLength(1), reason: '"$line" was made');
      return made.single;
    }

    Offset inletOf(Finder canvas, PatchNodeId id, [int i = 0]) =>
        tester.getRect(nodeView(canvas, id)).topLeft +
        Offset(patchPortOffsetAlongEdge(i), 0);

    Offset outletOf(Finder canvas, PatchNodeId id, [int i = 0]) =>
        tester.getRect(nodeView(canvas, id)).bottomLeft +
        Offset(patchPortOffsetAlongEdge(i), 0);

    // A cable drag from [from] to [to] in [canvas]'s window.
    Future<void> wire(Finder canvas, Offset from, Offset to) async {
      final cables = editor().graph.cables.length;
      final pointer = await tester.startGesture(from, view: viewOf(canvas));
      await tester.pump();
      await pointer.moveTo(Offset.lerp(from, to, 0.5)!);
      await tester.pump();
      await pointer.moveTo(to);
      await tester.pump();
      await pointer.up();
      await tester.pumpAndSettle();
      expect(editor().graph.cables, hasLength(cables + 1));
    }

    Future<void> chord(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    // Opens [box] from its node menu in the main window.
    Future<void> openSubpatch(PatchNodeId box) async {
      final line = nodeView(mainCanvas(), box);
      final g = await tester.startGesture(
        tester.getCenter(line),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PatcherSurface.openSubpatchItemKey));
      await tester.pumpAndSettle();
      expect(find.byType(SubpatchWindowView), findsOneWidget);
      expect(tester.binding.platformDispatcher.views, hasLength(2));
    }

    // ── Launch 1 ─────────────────────────────────────────────────────────
    final first = await launch('launch-1', newPath: dir);

    // The parent: a sine, the subpatch box, a dac.
    final sine = await create(mainCanvas(), const Offset(300, 80), '~sine 440');
    final box = await create(
      mainCanvas(),
      const Offset(300, 220),
      'patcher gain',
    );
    final dac = await create(mainCanvas(), const Offset(300, 360), '~dac');
    expect(box.type, Obj.patcher);
    expect(editor().subpatchNameOf(box.id), 'gain');
    expect(box.inputs, isEmpty, reason: 'nothing inside yet');

    // Open it: a second window, showing the (empty) inside.
    await openSubpatch(box.id);
    expect(
      tester.widget<Text>(find.byKey(SubpatchWindowView.titleKey)).data,
      'gain',
    );
    expect(
      find.descendant(
        of: windowCanvas(),
        matching: find.byType(PatcherNodeView),
      ),
      findsNothing,
    );

    // Build the inside, in the window.
    final inlet = await create(
      windowCanvas(),
      const Offset(120, 60),
      '~inlet 0',
    );
    final gain = await create(windowCanvas(), const Offset(120, 180), '~* 0.5');
    final outlet = await create(
      windowCanvas(),
      const Offset(120, 300),
      '~outlet 0',
    );
    for (final n in [inlet, gain, outlet]) {
      expect(n.container, box.id, reason: '${n.type} is inside the box');
    }
    await wire(
      windowCanvas(),
      outletOf(windowCanvas(), inlet.id),
      inletOf(windowCanvas(), gain.id),
    );
    await wire(
      windowCanvas(),
      outletOf(windowCanvas(), gain.id),
      inletOf(windowCanvas(), outlet.id),
    );

    // Back in the parent, the box has the pins its boundary objects define,
    // drawn on the box itself.
    expect(box.inputs, hasLength(1));
    expect(box.outputs, hasLength(1));
    final boxFace = tester.widget<PatchObjectBox>(
      find.descendant(
        of: nodeView(mainCanvas(), box.id),
        matching: find.byType(PatchObjectBox),
      ),
    );
    expect(boxFace.inputPortXs, hasLength(1));
    expect(boxFace.outputPortXs, hasLength(1));

    // Wire the parent through it: sine → gain → dac.
    await wire(
      mainCanvas(),
      outletOf(mainCanvas(), sine.id),
      inletOf(mainCanvas(), box.id),
    );
    await wire(
      mainCanvas(),
      outletOf(mainCanvas(), box.id),
      inletOf(mainCanvas(), dac.id),
    );

    // The cable the engine records on the `~inlet` is drawn on the box's pin
    // in the main window, and not at all inside the subpatch.
    final into = editor().graph.cables.singleWhere(
      (c) => c.source.nodeId == sine.id,
    );
    expect(into.target.nodeId, inlet.id);
    PatcherCableLayer layerIn(Finder canvas) =>
        tester.widget<PatcherCableLayer>(
          find.descendant(of: canvas, matching: find.byType(PatcherCableLayer)),
        );
    expect(
      layerIn(mainCanvas()).portPositions[into.target],
      box.position + Offset(patchPortOffsetAlongEdge(0), 0),
    );
    expect(layerIn(windowCanvas()).portPositions[into.target], isNull);

    // Place on master and start: the sine is heard through the subpatch.
    await tester.tap(find.byKey(PatchPlacementBar.placeSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('master').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PatchPlacementBar.startStopKey));
    await tester.pumpAndSettle();
    await untilMounted();
    expect(loudness(), greaterThan(0.05), reason: 'heard through the box');

    // Delete the gain stage inside: the path through the box is broken.
    await tester.tap(nodeView(windowCanvas(), gain.id));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(editor().graph.nodeById(gain.id), isNull);
    loudness(20);
    expect(loudness(), lessThan(1e-4), reason: 'nothing gets through');

    // Ctrl+Z in the *main* window undoes the edit made in the subpatch's.
    await tester.tapAt(
      tester.getTopLeft(mainCanvas()) + const Offset(700, 500),
    );
    await tester.pumpAndSettle();
    await chord(LogicalKeyboardKey.keyZ);
    expect(editor().graph.nodeById(gain.id), isNotNull);
    expect(nodeView(windowCanvas(), gain.id), findsOneWidget);
    loudness(20);
    expect(loudness(), greaterThan(0.05), reason: 'back after undo');
    await chord(LogicalKeyboardKey.keyY);
    expect(editor().graph.nodeById(gain.id), isNull);
    loudness(20);
    expect(loudness(), lessThan(1e-4), reason: 'gone again after redo');
    await chord(LogicalKeyboardKey.keyZ);
    expect(editor().graph.nodeById(gain.id), isNotNull);

    // Save through the File menu.
    await tester.tap(
      find.descendant(
        of: find.byType(ProjectMenu),
        matching: find.text('untitled'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(first.project.isDirty.value, isFalse);

    // ── Launch 2: reopen ─────────────────────────────────────────────────
    final second = await launch('launch-2');
    // Launch 1's surface is gone, and its window with it.
    expect(find.byType(SubpatchWindowView), findsNothing);
    await first.engine.dispose();
    first.project.dispose();
    first.settings.dispose();
    first.session.dispose();

    final reloaded = editor();
    final reBox = reloaded.graph.nodes.singleWhere(
      (n) => n.type == Obj.patcher,
    );
    expect(reloaded.subpatchNameOf(reBox.id), 'gain');
    expect(reloaded.nodesIn(reBox.id).map((n) => n.type).toSet(), {
      Obj.dInlet,
      Obj.dMultiply,
      Obj.dOutlet,
    });
    expect(reBox.inputs, hasLength(1));
    expect(reBox.outputs, hasLength(1));
    // Two cables inside, two in the parent wired through the box.
    expect(reloaded.graph.cables, hasLength(4));

    await openSubpatch(reBox.id);
    expect(
      find.descendant(
        of: windowCanvas(),
        matching: find.byType(PatcherNodeView),
      ),
      findsNWidgets(3),
    );

    // Loaded stopped, placement kept: start it and it sounds again.
    await tester.tap(find.byKey(PatchPlacementBar.startStopKey));
    await tester.pumpAndSettle();
    await untilMounted();
    expect(loudness(), greaterThan(0.05), reason: 'heard after reopening');

    // A window that goes while one of its fields still holds the keyboard —
    // an object box half typed, then another patch opened — must let the
    // platform finish with that field before the window is destroyed. The
    // Windows embedder fails every text input call for a view that is gone
    // (CI on PR #555); the check above stands in for it here.
    final windowCanvas2 = windowCanvas();
    final at = tester.getTopLeft(windowCanvas2) + const Offset(400, 400);
    await tester.tapAt(at, view: viewOf(windowCanvas2));
    await tester.pump();
    await tester.tapAt(at, view: viewOf(windowCanvas2));
    await tester.pumpAndSettle();
    final typing = find.descendant(
      of: windowCanvas2,
      matching: find.byKey(PatchInlineObjectBox.fieldKey),
    );
    tester.binding.focusedEditable = null;
    await tester.enterText(typing, '~sin');
    await tester.pumpAndSettle();
    second.engine.patchLibrary.newPatch();
    await tester.pumpAndSettle();
    expect(find.byType(SubpatchWindowView), findsNothing);
    await textInput.drain();
    await tester.pumpAndSettle();
    expect(tester.binding.platformDispatcher.views, hasLength(1));
    expect(textInput.errors, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await textInput.drain();
    expect(textInput.errors, isEmpty);
    await second.engine.dispose();
    second.project.dispose();
    second.settings.dispose();
    second.session.dispose();
  });
}
