import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/fader/phi_fader.dart';
import 'package:phi/design/widgets/patcher/patch_node_frame.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette.dart';
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
  });
}
