import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/fader/phi_fader.dart';
import 'package:phi/design/widgets/patcher/patch_gui_object.dart';
import 'package:phi/design/widgets/patcher/patch_object_box.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/surfaces/patcher/create/patch_inline_object_box.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette.dart';
import 'package:phi/surfaces/patcher/patch_canvas_mode.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:phi/surfaces/patcher/patcher_surface.dart';
import 'package:phi/surfaces/patcher/placement/patch_placement_bar.dart';
import 'package:phi/surfaces/patcher/reference/patch_reference_panel.dart';
import 'package:yse/yse.dart';

import '../../engine/test_doubles/fake_patcher_gateway.dart';
import '../../engine/test_doubles/fake_yse_gateway.dart';

void main() {
  group('PatcherSurface — offline', () {
    late FakeYseGateway gateway;
    late FakePatcherGateway patcherGateway;
    late PhiEngine engine;

    setUp(() {
      gateway = FakeYseGateway();
      patcherGateway = FakePatcherGateway();
      engine = PhiEngine(
        gateway,
        patcherGateway: patcherGateway,
        telemetryInterval: const Duration(milliseconds: 50),
      );
      NodeTypeRegistry.instance.clear();
    });

    tearDown(() async {
      await engine.dispose();
      await gateway.dispose();
      NodeTypeRegistry.instance.clear();
    });

    testWidgets('renders the offline placeholder before engine starts', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PatcherSurface(engine: engine)),
        ),
      );

      expect(
        find.text('patcher offline · start the engine'.toUpperCase()),
        findsOneWidget,
      );
    });
  });

  group('PatcherSurface — running', () {
    late FakeYseGateway gateway;
    late FakePatcherGateway patcherGateway;
    late PhiEngine engine;

    setUp(() {
      gateway = FakeYseGateway();
      patcherGateway = FakePatcherGateway();
      engine = PhiEngine(
        gateway,
        patcherGateway: patcherGateway,
        telemetryInterval: const Duration(milliseconds: 50),
      );
      NodeTypeRegistry.instance.clear();
      engine.start();
    });

    tearDown(() async {
      await engine.dispose();
      await gateway.dispose();
      NodeTypeRegistry.instance.clear();
    });

    testWidgets('seeds three nodes and two cables on first build', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PatcherSurface(engine: engine)),
        ),
      );
      // First frame triggers the seed in initState; pump once more so the
      // ListenableBuilder picks up the graph changes.
      await tester.pump();

      expect(find.byType(PatcherNodeView), findsNWidgets(3));
      // Two of them — `~sine` and `~dac` — are object boxes (issue #379); the
      // `.slider` is a bare fader, a GUI object with no frame at all (#381).
      expect(find.byType(PatchObjectBox), findsNWidgets(2));
      expect(find.byType(PatchGuiObject), findsOneWidget);
      expect(engine.patcher.graph.cables, hasLength(2));
      expect(patcherGateway.cables, hasLength(2));
      // The seed mounts the patcher as a source once a `~dac` exists — the
      // surface → controller → gateway audio path survives the multi-instance
      // generalisation (issue #219).
      expect(patcherGateway.mounted, isTrue);
    });

    testWidgets('dragging the slider pushes a sendFloat through the gateway', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PatcherSurface(engine: engine)),
        ),
      );
      await tester.pump();

      final faderFinder = find.byType(PhiFader);
      expect(faderFinder, findsOneWidget);
      final PhiFader fader = tester.widget(faderFinder);
      fader.onChanged(0.25);
      await tester.pump();

      final sendFloats = patcherGateway.calls
          .where((c) => c.startsWith('sendFloat'))
          .toList();
      expect(sendFloats, isNotEmpty);
      expect(sendFloats.last, endsWith(':0:0.250'));
    });

    testWidgets('dragging a palette entry lands a node at the drop point', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PatcherSurface(engine: engine)),
        ),
      );
      await tester.pump();

      final controller = engine.patcher;
      final before = {for (final n in controller.graph.nodes) n.id};
      expect(before, hasLength(3)); // the seeded slider · sine · dac

      final canvas = find.byType(PatcherCanvas);
      final dropGlobal = tester.getCenter(canvas);

      // Drive a real Draggable → DragTarget drop (the canonical gesture recipe).
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(PatcherPalette.entryKey(Obj.dSine))),
      );
      await tester.pump();
      await gesture.moveTo(dropGlobal);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final added = controller.graph.nodes
          .where((n) => !before.contains(n.id))
          .toList();
      expect(added, hasLength(1));
      expect(added.single.type, Obj.dSine);

      // It landed at the drop point in canvas-local coordinates (the surface
      // sits at identity transform, so canvas-local = global − canvas origin).
      final expected = dropGlobal - tester.getTopLeft(canvas);
      expect((added.single.position - expected).distance, lessThan(1.0));
    });

    /// One node's chrome, named by its **logical id** rather than by what it
    /// prints: an object box prints its type and arguments (issue #379), and
    /// the seeded patch already holds a `~sine` and a `~dac` of its own — the
    /// friendly titles that used to tell a dropped node apart are gone with the
    /// headers. Kind-agnostic, so it names a bare GUI control just as well.
    Finder viewOf(PatchNode node) => find.byWidgetPredicate(
      (w) => w is PatcherNodeView && w.node.id == node.id,
    );

    /// Drop a palette entry of [type] on the canvas centre and return the node
    /// it created — the newest in the graph.
    Future<PatchNode> dropOnCanvas(WidgetTester tester, String type) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(PatcherPalette.entryKey(type))),
      );
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byType(PatcherCanvas)));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      return engine.patcher.graph.nodes.last;
    }

    testWidgets('tapping a canvas node shows its reference', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PatcherSurface(engine: engine)),
        ),
      );
      await tester.pump();

      // Nothing selected yet → the reference panel is empty.
      expect(find.byKey(PatchReferencePanel.emptyKey), findsOneWidget);

      // Drag a `~dac` onto the visible centre of the canvas, then tap it.
      final dac = await dropOnCanvas(tester, Obj.dDac);
      await tester.tap(viewOf(dac));
      await tester.pump();

      // The reference now documents the tapped node's engine metadata.
      expect(find.byKey(PatchReferencePanel.emptyKey), findsNothing);
      expect(find.text('audio output'), findsOneWidget);
    });

    // ─── node context menu + live param values (issue #356) ───────────────

    Future<void> rightClick(WidgetTester tester, Finder target) async {
      final g = await tester.startGesture(
        tester.getCenter(target),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
    }

    testWidgets('right-clicking a node opens the verbs — and no params dialog '
        'is among them any more', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PatcherSurface(engine: engine)),
        ),
      );
      await tester.pump();

      final sine = await dropOnCanvas(tester, Obj.dSine);
      await rightClick(tester, viewOf(sine));

      expect(find.text('duplicate · ctrl+d'), findsOneWidget);
      expect(find.text('delete · del'), findsOneWidget);
      // The verb's whole content was "open the params dialog", and the dialog
      // is gone: arguments are typed on the box itself (issue #382).
      expect(find.text('edit parameters…'), findsNothing);
    });

    testWidgets('double-clicking an object box opens it for typing, not a '
        'dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PatcherSurface(engine: engine)),
        ),
      );
      await tester.pump();

      final sine = await dropOnCanvas(tester, Obj.dSine);
      final at = tester.getCenter(viewOf(sine));
      await tester.tapAt(at);
      await tester.pump();
      await tester.tapAt(at);
      await tester.pumpAndSettle();

      // The surface wires the catalogue into the canvas, which is what lets the
      // box complete against the same source the palette renders.
      expect(find.byKey(PatcherCanvas.inlineEditKey), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(PatchInlineObjectBox.fieldKey))
            .controller!
            .text,
        'sine 440',
      );
    });

    testWidgets('the menu duplicates and deletes the node it was opened on', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PatcherSurface(engine: engine)),
        ),
      );
      await tester.pump();

      final controller = engine.patcher;
      final sine = await dropOnCanvas(tester, Obj.dSine);
      final afterDrop = controller.graph.nodes.length;

      await rightClick(tester, viewOf(sine));
      await tester.tap(find.text('duplicate · ctrl+d'));
      await tester.pumpAndSettle();
      expect(controller.graph.nodes, hasLength(afterDrop + 1));

      // The copy became the selection, so `delete` from its menu takes it back.
      // The copy is the newest node in the graph.
      await rightClick(tester, viewOf(controller.graph.nodes.last));
      await tester.tap(find.text('delete · del'));
      await tester.pumpAndSettle();
      expect(controller.graph.nodes, hasLength(afterDrop));
    });

    testWidgets('selecting a node shows its current arg values, which follow '
        'an edit and its undo', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PatcherSurface(engine: engine)),
        ),
      );
      await tester.pump();

      final controller = engine.patcher;
      final sine = await dropOnCanvas(tester, Obj.dSine);
      await tester.tap(viewOf(sine));
      await tester.pump();

      // Selection alone answers "what is this set to".
      final value = find.byKey(PatchReferencePanel.valueKey('frequency'));
      expect(value, findsOneWidget);
      expect(find.text('= 440'), findsOneWidget);

      controller.applyParams(sine.id, '660');
      await tester.pump();
      expect(find.text('= 660'), findsOneWidget);

      controller.undo();
      await tester.pump();
      expect(find.text('= 440'), findsOneWidget);
    });

    // ─── edit / run mode (issue #378) ─────────────────────────────────────

    testWidgets('the placement bar\'s toggle puts the canvas in run mode and '
        'drops the selection', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PatcherSurface(engine: engine)),
        ),
      );
      await tester.pump();

      final controller = engine.patcher;
      PatchCanvasMode canvasMode() =>
          tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode;

      expect(canvasMode(), PatchCanvasMode.edit);

      final sine = await dropOnCanvas(tester, Obj.dSine);
      await tester.tap(viewOf(sine));
      await tester.pump();
      expect(controller.graph.selectedNodes, isNotEmpty);

      // The toggle is chrome in a *different widget* from the canvas it
      // governs, so this is the wire between them.
      await tester.tap(find.byKey(PatchPlacementBar.modeKey));
      await tester.pumpAndSettle();

      expect(canvasMode(), PatchCanvasMode.run);
      // A selection is an editing state: nothing in run mode can act on it, so
      // nothing in run mode should keep drawing a ring around it.
      expect(controller.graph.selectedNodes, isEmpty);

      await tester.tap(find.byKey(PatchPlacementBar.modeKey));
      await tester.pumpAndSettle();
      expect(canvasMode(), PatchCanvasMode.edit);
    });

    testWidgets('the mode is performance state — a fresh surface starts in '
        'edit', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PatcherSurface(engine: engine)),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(PatchPlacementBar.modeKey));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode,
        PatchCanvasMode.run,
      );

      // Re-mounted from scratch, exactly as a reopened project does it: the
      // mode is never written anywhere, so it comes back in edit.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PatcherSurface(engine: engine)),
        ),
      );
      await tester.pump();

      expect(
        tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode,
        PatchCanvasMode.edit,
      );
    });
  });
}
