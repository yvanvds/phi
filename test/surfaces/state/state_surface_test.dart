import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/state_machine/state_node_frame.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/surfaces/state/state_surface.dart';

import '../../engine/test_doubles/fake_yse_gateway.dart';

void main() {
  group('StateSurface — offline', () {
    late FakeYseGateway gateway;
    late PhiEngine engine;

    setUp(() {
      gateway = FakeYseGateway();
      engine = PhiEngine(
        gateway,
        telemetryInterval: const Duration(milliseconds: 50),
      );
    });

    tearDown(() async {
      await engine.dispose();
      await gateway.dispose();
    });

    testWidgets('renders the offline placeholder before engine starts', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StateSurface(engine: engine)),
        ),
      );

      expect(
        find.text('state offline · start the engine'.toUpperCase()),
        findsOneWidget,
      );
    });
  });

  group('StateSurface — running', () {
    late FakeYseGateway gateway;
    late PhiEngine engine;

    setUp(() {
      gateway = FakeYseGateway();
      engine = PhiEngine(
        gateway,
        telemetryInterval: const Duration(milliseconds: 50),
      );
      engine.start();
    });

    tearDown(() async {
      await engine.dispose();
      await gateway.dispose();
    });

    testWidgets('seeds two states and one transition on first build', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StateSurface(engine: engine)),
        ),
      );
      // First frame triggers the seed in initState; pump again so the
      // ListenableBuilder picks up the graph changes.
      await tester.pump();

      expect(find.byType(StateNodeFrame), findsNWidgets(2));
      expect(engine.stateMachine.graph.states, hasLength(2));
      expect(engine.stateMachine.graph.transitions, hasLength(1));
    });

    testWidgets('seed marks the first state as the live one', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StateSurface(engine: engine)),
        ),
      );
      await tester.pump();

      final activeId = engine.stateMachine.graph.activeStateId;
      expect(activeId, isNotNull);
      expect(engine.stateMachine.graph.stateById(activeId!)?.name, 'intro');
      expect(find.text('● LIVE'), findsOneWidget);
    });
  });
}
