import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/fader/phi_fader.dart';
import 'package:phi/design/widgets/patcher/patch_node_frame.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/surfaces/patcher/patcher_surface.dart';

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
  });
}
