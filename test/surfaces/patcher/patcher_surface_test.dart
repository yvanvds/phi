import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/fader/phi_fader.dart';
import 'package:phi/design/widgets/patcher/patch_node_frame.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette.dart';
import 'package:phi/surfaces/patcher/params/patch_params_dialog.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/patcher_surface.dart';
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

      expect(find.byType(PatchNodeFrame), findsNWidgets(3));
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

    testWidgets('tapping a canvas node shows its reference', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PatcherSurface(engine: engine)),
        ),
      );
      await tester.pump();

      // Nothing selected yet → the reference panel is empty.
      expect(find.byKey(PatchReferencePanel.emptyKey), findsOneWidget);

      // Drag a `~dac` onto the visible centre of the canvas, then tap it. Its
      // header reads its own type id (`~DAC`), unique against the seeded
      // `OUT · L/R` dac, so we can find and tap exactly this node.
      final canvas = find.byType(PatcherCanvas);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(PatcherPalette.entryKey(Obj.dDac))),
      );
      await tester.pump();
      await gesture.moveTo(tester.getCenter(canvas));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text(Obj.dDac.toUpperCase()));
      await tester.pump();

      // The reference now documents the tapped node's engine metadata.
      expect(find.byKey(PatchReferencePanel.emptyKey), findsNothing);
      expect(find.text('audio output'), findsOneWidget);
    });

    // ─── node context menu + live param values (issue #356) ───────────────

    /// Drop a palette entry of [type] on the canvas centre and return its
    /// header finder — the dropped node's header shows its raw type id, which
    /// the friendly-titled seeded nodes never do, so it names exactly this one.
    Future<Finder> dropOnCanvas(WidgetTester tester, String type) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(PatcherPalette.entryKey(type))),
      );
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byType(PatcherCanvas)));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      return find.text(type.toUpperCase());
    }

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

    testWidgets('right-clicking a node opens the verbs, and edit parameters '
        'reaches the dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PatcherSurface(engine: engine)),
        ),
      );
      await tester.pump();

      final sine = await dropOnCanvas(tester, Obj.dSine);
      await rightClick(tester, sine);

      expect(find.text('edit parameters…'), findsOneWidget);
      expect(find.text('duplicate · ctrl+d'), findsOneWidget);
      expect(find.text('delete · del'), findsOneWidget);

      await tester.tap(find.text('edit parameters…'));
      await tester.pumpAndSettle();

      // The same dialog double-click opens — the menu is a second door, not a
      // second implementation.
      expect(find.byType(PatchParamsDialog), findsOneWidget);
      expect(
        find.byKey(PatchParamsDialog.fieldKey('frequency')),
        findsOneWidget,
      );
    });

    testWidgets('a GUI object is offered no parameters to edit', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PatcherSurface(engine: engine)),
        ),
      );
      await tester.pump();

      // `.slider` is operated through its live body and documents no params, so
      // offering a dialog would open one with nothing in it.
      final slider = await dropOnCanvas(tester, Obj.gSlider);
      await rightClick(tester, slider);

      expect(find.text('edit parameters…'), findsNothing);
      expect(find.text('duplicate · ctrl+d'), findsOneWidget);
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

      await rightClick(tester, sine);
      await tester.tap(find.text('duplicate · ctrl+d'));
      await tester.pumpAndSettle();
      expect(controller.graph.nodes, hasLength(afterDrop + 1));

      // The copy became the selection, so `delete` from its menu takes it back.
      await rightClick(tester, find.text(Obj.dSine.toUpperCase()).first);
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
      await tester.tap(sine);
      await tester.pump();

      // Selection alone answers "what is this set to".
      final value = find.byKey(PatchReferencePanel.valueKey('frequency'));
      expect(value, findsOneWidget);
      expect(find.text('= 440'), findsOneWidget);

      final node = controller.graph.nodes.firstWhere(
        (n) => n.title == Obj.dSine,
      );
      controller.applyParams(node.id, '660');
      await tester.pump();
      expect(find.text('= 660'), findsOneWidget);

      controller.undo();
      await tester.pump();
      expect(find.text('= 440'), findsOneWidget);
    });
  });
}
