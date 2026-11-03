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
import 'package:phi/domain/patcher/patch_port_kind.dart';
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
import 'package:phi/surfaces/patcher/create/patch_inline_object_box.dart';
import 'package:phi/surfaces/patcher/patch_canvas_mode.dart';
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
import '../test/surfaces/patcher/test_support/until_window_active.dart';

/// End-to-end proof of encapsulate and de-encapsulate (issue #552), through
/// the real [PhiApp] — rail navigation, fonts, layout, the node menu, the
/// subpatch's own native window — on the real patcher engine
/// ([RealPatcherGateway] over an offline libyse session). Only the audio
/// device, MIDI and the project store are fakes.
///
/// The performer builds `~sine` → `~* 0.5` → `~dac`, starts it on master and
/// hears it. Selecting the `~*` and pressing `Ctrl+Shift+E` puts it in a new
/// subpatch box with a `~inlet` and a `~outlet`; the mode stays `EDIT`, the
/// sine is still heard through the box, and the box opens onto what was moved.
/// *De-encapsulate* from the box's menu puts the `~*` back where it was, wired
/// straight again, and closes the window. `Ctrl+Z` twice walks back through
/// both, one step each, and the patch sounds at every step.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: Ctrl+Shift+E moves a selection into a subpatch that '
      'still carries the signal; de-encapsulate and undo walk it back', (
    tester,
  ) async {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
    addTearDown(System.instance.close);
    await tester.binding.setSurfaceSize(const Size(1600, 1000));

    final gateway = RealPatcherGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      patcherGateway: gateway,
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final settings = AppSettingsController(FakeAppSettingsStore());
    final project = ProjectController(
      session: session,
      settings: settings,
      storeFactory: (_) => FakeProjectStore(codecs: defaultEntityCodecs()),
      journalStoreFactory: (_) => FakeJournalStore(),
      seedRegistry: seedDefaultProject,
      autosaveIntervalOverride: const Duration(hours: 1),
    );
    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: project,
        directoryPicker: FakeProjectDirectoryPicker(
          newLocationPath: '/projects/encapsulate.phi',
        ),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

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

    // Double-clicks the empty grid at [scene], types [line] into the inline
    // object box and presses Enter. Returns the object made.
    Future<PatchNode> create(Offset scene, String line) async {
      final canvas = mainCanvas();
      final at = tester.getTopLeft(canvas) + scene;
      final before = editor().graph.nodes.map((n) => n.id).toSet();
      final field = find.descendant(
        of: canvas,
        matching: find.byKey(PatchInlineObjectBox.fieldKey),
      );
      for (var attempt = 0; attempt < 3; attempt++) {
        await untilWindowActive(tester);
        if (field.evaluate().isEmpty) {
          await tester.tapAt(at);
          await tester.pump();
          await tester.tapAt(at);
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

    Offset inletOf(PatchNodeId id) =>
        tester.getRect(nodeView(mainCanvas(), id)).topLeft +
        Offset(patchPortOffsetAlongEdge(0), 0);

    Offset outletOf(PatchNodeId id) =>
        tester.getRect(nodeView(mainCanvas(), id)).bottomLeft +
        Offset(patchPortOffsetAlongEdge(0), 0);

    Future<void> wire(Offset from, Offset to) async {
      final cables = editor().graph.cables.length;
      final pointer = await tester.startGesture(from);
      await tester.pump();
      await pointer.moveTo(Offset.lerp(from, to, 0.5)!);
      await tester.pump();
      await pointer.moveTo(to);
      await tester.pump();
      await pointer.up();
      await tester.pumpAndSettle();
      expect(editor().graph.cables, hasLength(cables + 1));
    }

    Future<void> chord(LogicalKeyboardKey key, {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    Future<void> menuItem(PatchNodeId id, Key item) async {
      final g = await tester.startGesture(
        tester.getCenter(nodeView(mainCanvas(), id)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(item));
      await tester.pumpAndSettle();
    }

    Set<String> topLevelTypes() => {
      for (final n in editor().nodesIn(null)) n.type,
    };

    // ── A flat chain, heard on master ─────────────────────────────────────
    final sine = await create(const Offset(300, 80), '~sine 440');
    final gain = await create(const Offset(300, 220), '~* 0.5');
    final dac = await create(const Offset(300, 360), '~dac');
    final gainAt = gain.position;
    await wire(outletOf(sine.id), inletOf(gain.id));
    await wire(outletOf(gain.id), inletOf(dac.id));

    await tester.tap(find.byKey(PatchPlacementBar.placeSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('master').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PatchPlacementBar.startStopKey));
    await tester.pumpAndSettle();
    await untilMounted();
    expect(loudness(), greaterThan(0.05), reason: 'heard flat');

    // ── Ctrl+Shift+E ──────────────────────────────────────────────────────
    await tester.tap(nodeView(mainCanvas(), gain.id));
    await tester.pumpAndSettle();
    expect(editor().graph.selectedNodes, {gain.id});
    await chord(LogicalKeyboardKey.keyE, shift: true);

    expect(
      tester.widget<PatcherCanvas>(mainCanvas()).mode,
      PatchCanvasMode.edit,
      reason: 'Ctrl+Shift+E is not the Ctrl+E mode flip',
    );
    expect(topLevelTypes(), {Obj.dSine, Obj.patcher, Obj.dDac});
    final box = editor()
        .nodesIn(null)
        .singleWhere((n) => n.type == Obj.patcher);
    expect(box.position, gainAt, reason: 'the box takes the selection place');
    expect(editor().graph.selectedNodes, {box.id});
    expect(editor().containerOf(gain.id), box.id);
    expect(box.inputs.map((p) => p.kind), [PatchPortKind.audio]);
    expect(box.outputs.map((p) => p.kind), [PatchPortKind.audio]);
    final face = tester.widget<PatchObjectBox>(
      find.descendant(
        of: nodeView(mainCanvas(), box.id),
        matching: find.byType(PatchObjectBox),
      ),
    );
    expect(face.inputPortXs, hasLength(1));
    expect(face.outputPortXs, hasLength(1));
    expect(nodeView(mainCanvas(), gain.id), findsNothing);
    loudness(20);
    expect(loudness(), greaterThan(0.05), reason: 'heard through the box');

    // The box opens onto what was moved, its pins made for it.
    await menuItem(box.id, PatcherSurface.openSubpatchItemKey);
    expect(find.byType(SubpatchWindowView), findsOneWidget);
    expect(editor().nodesIn(box.id).map((n) => n.type).toSet(), {
      Obj.dInlet,
      Obj.dMultiply,
      Obj.dOutlet,
    });
    expect(
      find.descendant(
        of: windowCanvas(),
        matching: find.byType(PatcherNodeView),
      ),
      findsNWidgets(3),
    );
    expect(nodeView(windowCanvas(), gain.id), findsOneWidget);

    // ── De-encapsulate, from the box's menu ───────────────────────────────
    await menuItem(box.id, PatcherSurface.deencapsulateItemKey);

    expect(topLevelTypes(), {Obj.dSine, Obj.dMultiply, Obj.dDac});
    expect(editor().graph.nodeById(box.id), isNull);
    expect(editor().graph.nodeById(gain.id)!.position, gainAt);
    expect(editor().graph.nodes, hasLength(3), reason: 'the pins went');
    expect(editor().graph.cables, hasLength(2));
    expect(find.byType(SubpatchWindowView), findsNothing, reason: 'box gone');
    expect(nodeView(mainCanvas(), gain.id), findsOneWidget);
    loudness(20);
    expect(loudness(), greaterThan(0.05), reason: 'heard flat again');

    // ── Ctrl+Z walks back one step at a time ──────────────────────────────
    await tester.tapAt(
      tester.getTopLeft(mainCanvas()) + const Offset(700, 500),
    );
    await tester.pumpAndSettle();
    await chord(LogicalKeyboardKey.keyZ);
    expect(topLevelTypes(), {Obj.dSine, Obj.patcher, Obj.dDac});
    expect(editor().containerOf(gain.id), box.id, reason: 'same box id');
    loudness(20);
    expect(loudness(), greaterThan(0.05), reason: 'undo de-encapsulate');

    await chord(LogicalKeyboardKey.keyZ);
    expect(topLevelTypes(), {Obj.dSine, Obj.dMultiply, Obj.dDac});
    expect(editor().graph.nodes, hasLength(3));
    expect(editor().graph.nodeById(gain.id)!.position, gainAt);
    loudness(20);
    expect(loudness(), greaterThan(0.05), reason: 'undo encapsulate');

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await engine.dispose();
    project.dispose();
    settings.dispose();
    session.dispose();
  });
}
