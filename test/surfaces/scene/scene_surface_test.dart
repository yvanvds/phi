import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/toggle/phi_toggle.dart';
import 'package:phi/domain/scene/pick_ray.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/surfaces/scene/scene_surface.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../engine/test_doubles/fake_midi_gateway.dart';
import '../../engine/test_doubles/fake_scene_renderer.dart';
import '../../engine/test_doubles/fake_yse_gateway.dart';

void main() {
  late FakeYseGateway yse;
  late FakeSceneRenderer renderer;
  late FakeMidiGateway midi;
  late PhiEngine engine;

  setUp(() {
    yse = FakeYseGateway();
    renderer = FakeSceneRenderer();
    midi = FakeMidiGateway();
    engine = PhiEngine(
      yse,
      sceneRenderer: renderer,
      midiGateway: midi,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    engine.start();
  });

  tearDown(() async {
    await engine.dispose();
    await yse.dispose();
  });

  Future<void> pumpSurface(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: SceneSurface(engine: engine)));
    await tester.pump(const Duration(milliseconds: 20)); // let the ticker run
  }

  testWidgets('renders a fallback when no renderer is wired', (tester) async {
    final bare = PhiEngine(FakeYseGateway());
    await tester.pumpWidget(MaterialApp(home: SceneSurface(engine: bare)));
    expect(find.text('Scene renderer not wired'), findsOneWidget);
    await bare.dispose();
  });

  testWidgets('seeds the camera and a placeholder agent on mount', (
    tester,
  ) async {
    await pumpSurface(tester);
    expect(renderer.calls, contains('setCamera'));
    expect(renderer.calls, contains('setAgents:1'));
    expect(renderer.lastAgents, hasLength(1));
  });

  testWidgets('installs pointer picking with the surface as handler', (
    tester,
  ) async {
    await pumpSurface(tester);
    expect(renderer.calls, contains('installPicking'));
    expect(renderer.installedHandler, isNotNull);
  });

  testWidgets('an idle Scene schedules no frames (never blocks settle)', (
    tester,
  ) async {
    // Nothing picked or grabbed → the ticker stays parked, so the tree
    // settles instead of spinning forever.
    await tester.pumpWidget(MaterialApp(home: SceneSurface(engine: engine)));
    await tester.pumpAndSettle();
    expect(renderer.calls.where((c) => c.startsWith('setSelection')), isEmpty);
  });

  testWidgets('clearing the selection removes the highlight', (tester) async {
    await pumpSurface(tester);
    renderer.installedHandler!.select(null);
    await tester.pump();
    expect(renderer.calls, contains('setSelection:null'));
  });

  testWidgets('the installed handler forwards pick/grab to the field', (
    tester,
  ) async {
    await pumpSurface(tester);
    final handler = renderer.installedHandler!;

    // No agents are alive before playback, so a pick misses and the grab
    // helpers are safe no-ops (they forward to EngineMidiController).
    final ray = PickRay(
      origin: Vector3(0, 0, -10),
      direction: Vector3(0, 0, 1),
    );
    expect(handler.pick(ray), isNull);
    expect(handler.agentPosition(0), isNull);
    expect(() {
      handler
        ..grab(0)
        ..moveGrabTo(Vector3.zero())
        ..releaseGrab()
        ..select(null);
    }, returnsNormally);
  });

  testWidgets('the dev toggle loads a pick-friendly demo set (issue #90)', (
    tester,
  ) async {
    await pumpSurface(tester);
    // The overlay toggle is present and starts off, so the scene still shows
    // just the seeded placeholder.
    final toggle = find.descendant(
      of: find.byKey(const Key('scene-pick-demo-toggle')),
      matching: find.byType(PhiToggle),
    );
    expect(toggle, findsOneWidget);
    expect(renderer.lastAgents, hasLength(1));

    // Flip it on: the controller seeds several well-separated agents and pushes
    // them to the renderer, and each is pickable by the installed handler.
    await tester.tap(toggle);
    await tester.pump();
    expect(renderer.lastAgents.length, greaterThan(1));
    final handler = renderer.installedHandler!;
    for (final agent in renderer.lastAgents) {
      final p = agent.position;
      final key = handler.pick(
        PickRay(origin: p + Vector3(0, 0, -10), direction: Vector3(0, 0, 1)),
      );
      expect(key, isNotNull, reason: 'each demo agent is pickable');
    }

    // Flip it off: the demo clears back to an empty scene.
    await tester.tap(toggle);
    await tester.pump();
    expect(renderer.lastAgents, isEmpty);
  });

  testWidgets('selecting a live agent puts the highlight on its position', (
    tester,
  ) async {
    // Play the demo chain (its spawn chip is active) until an agent is alive,
    // then pick it with a ray aimed straight at it — the field, not the GL
    // viewport, resolves the hit, so this stays headless and deterministic.
    engine.midi.play();
    await tester.pump(const Duration(milliseconds: 300));
    await pumpSurface(tester);

    final live = renderer.lastAgents;
    expect(live, isNotEmpty, reason: 'the demo note at ~0.6 beat is sounding');
    final target = live.first.position;
    final handler = renderer.installedHandler!;
    final key = handler.pick(
      PickRay(origin: target + Vector3(0, 0, -10), direction: Vector3(0, 0, 1)),
    );
    expect(key, isNotNull);

    // Advance two sub-tick frames (the surface ticker's first tick reports a
    // zero delta, so a second frame is needed to see a push) while staying
    // under the 16 ms playback interval, so no note-off despawns the agent out
    // from under the assertion.
    handler.select(key);
    await tester.pump(const Duration(milliseconds: 5));
    await tester.pump(const Duration(milliseconds: 5));
    expect(renderer.lastSelection, isNotNull);
    expect(renderer.calls, contains('setSelection:pos'));

    engine.midi.stop();
  });
}
