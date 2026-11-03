import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/design/widgets/toggle/phi_toggle.dart';
import 'package:phi/domain/scene/scene_agent.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/flutter_scene_renderer.dart';
import 'package:phi/engine/bridge/flutter_scene_view.dart';
import 'package:phi/engine/bridge/scene_view_status.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:vector_math/vector_math_64.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end: the real app opens the Scene on the production
/// `FlutterSceneRenderer` (Flutter GPU, issue #455). The 3D view comes up,
/// draws each agent in its voice colour where the pick math says it is (so the
/// picture is not mirrored against picking), and the real pointer picks, grabs,
/// orbits and zooms through it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  /// Let the engine's async work (static resources, paced GPU frames) land.
  Future<void> settleGpu(WidgetTester tester, {int frames = 12}) async {
    for (var i = 0; i < frames; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<(ByteData, int)> capture(WidgetTester tester) async {
    final boundary = tester.renderObject(
      find.byKey(FlutterSceneView.viewportKey),
    ) as RenderRepaintBoundary;
    final image = (await tester.runAsync(() => boundary.toImage()))!;
    final bytes = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    return (bytes, image.width);
  }

  /// The brightest pixel within [radius] logical pixels of [at] — the agent's
  /// core sits there, its halo and the bloom around it.
  Color brightestNear((ByteData, int) frame, Offset at, {int radius = 3}) {
    final (bytes, width) = frame;
    final height = bytes.lengthInBytes ~/ (width * 4);
    var best = const Color(0x00000000);
    var bestSum = -1;
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dx = -radius; dx <= radius; dx++) {
        final x = at.dx.round() + dx;
        final y = at.dy.round() + dy;
        if (x < 0 || y < 0 || x >= width || y >= height) continue;
        final o = (y * width + x) * 4;
        final r = bytes.getUint8(o);
        final g = bytes.getUint8(o + 1);
        final b = bytes.getUint8(o + 2);
        final a = bytes.getUint8(o + 3);
        if (r + g + b > bestSum) {
          bestSum = r + g + b;
          best = Color.fromARGB(a, r, g, b);
        }
      }
    }
    return best;
  }

  /// Whether [actual] reads as [voice]: the same dominant hue, not grey.
  void expectVoice(Color actual, Color voice, String what) {
    double d(double a, double b) => (a - b).abs();
    expect(
      d(actual.r, voice.r) + d(actual.g, voice.g) + d(actual.b, voice.b),
      lessThan(0.45),
      reason: '$what should draw in $voice, got $actual',
    );
  }

  testWidgets('scene: the 3D view draws agents and the pointer drives them', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final renderer = FlutterSceneRenderer();
    final engine = PhiEngine(
      FakeYseGateway(),
      sceneRenderer: renderer,
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    await tester.tap(railFor(SurfaceId.scene));
    await tester.pump();
    await settleGpu(tester);
    expect(
      renderer.status,
      SceneViewStatus.ready,
      reason: 'Flutter GPU is on in the runner: ${renderer.failure}',
    );
    expect(find.byKey(FlutterSceneView.unavailableKey), findsNothing);
    final viewport = find.byKey(FlutterSceneView.viewportKey);
    expect(viewport, findsOneWidget);
    // An idle Scene schedules no frames: the view redraws on demand.
    await tester.pumpAndSettle();

    final size = tester.getSize(viewport);
    final origin = tester.getTopLeft(viewport);

    // The surface's seed agent (voice 1) draws at the origin.
    var frame = await capture(tester);
    expectVoice(
      brightestNear(frame, renderer.project(Vector3.zero(), size)!),
      PhiColors.voice1,
      'the seed agent',
    );

    // Load the pick demo: agents on ±X, ±Y, +Z in distinct voices.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('scene-pick-demo-toggle')),
        matching: find.byType(PhiToggle),
      ),
    );
    await settleGpu(tester);
    expect(renderer.agents.length, 5);
    expect(renderer.graph!.agentCount, 5);
    frame = await capture(tester);

    const voices = [
      PhiColors.voice1,
      PhiColors.voice2,
      PhiColors.voice3,
      PhiColors.voice4,
      PhiColors.voice5,
    ];
    for (final SceneAgent agent in renderer.agents) {
      final at = renderer.project(agent.position, size)!;
      expectVoice(
        brightestNear(frame, at),
        voices[agent.voiceIndex],
        'the agent at ${agent.position}',
      );
    }
    // Right-handed, +Z up, seen from (6, 6, 4): +X runs to the left of the
    // origin, +Y to the right and +Z up — the picture is not mirrored.
    final plusX = renderer.project(Vector3(3, 0, 0), size)!;
    final plusY = renderer.project(Vector3(0, 3, 0), size)!;
    final centre = renderer.project(Vector3.zero(), size)!;
    final plusZ = renderer.project(Vector3(0, 0, 3), size)!;
    expect(plusX.dx, lessThan(centre.dx));
    expect(plusY.dx, greaterThan(centre.dx));
    expect(plusZ.dy, lessThan(centre.dy));

    // Click the +Z agent: it is selected (the shell rings it) and grabbed;
    // dragging right pulls it toward screen-right.
    final topAgent = renderer.agents.firstWhere((a) => a.position.z > 2);
    final grabAt = origin + renderer.project(topAgent.position, size)!;
    final gesture = await tester.startGesture(grabAt);
    await settleGpu(tester, frames: 3);
    expect(renderer.selection, isNotNull, reason: 'the click picked it');
    expect(
      renderer.selection!.distanceTo(topAgent.position),
      lessThan(0.5),
      reason: 'the selection rings the clicked agent',
    );
    expect(renderer.graph!.selectionVisible, isTrue);
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 25));
    }
    await settleGpu(tester, frames: 6);
    final pulled = renderer.agents.firstWhere((a) => a.voiceIndex == 4);
    final pulledAt = renderer.project(pulled.position, size)!;
    expect(
      pulledAt.dx,
      greaterThan(renderer.project(topAgent.position, size)!.dx + 20),
      reason: 'the grab pulled the agent toward the pointer',
    );
    await gesture.up();
    await settleGpu(tester, frames: 3);

    // A left-drag on empty space clears the selection and orbits the camera.
    final yaw = renderer.orbit.yaw;
    final empty = origin + Offset(size.width - 40, size.height - 40);
    final orbit = await tester.startGesture(empty);
    await orbit.moveBy(const Offset(60, 0));
    await orbit.moveBy(const Offset(60, 0));
    await orbit.up();
    await settleGpu(tester, frames: 3);
    expect(renderer.selection, isNull);
    expect(renderer.orbit.yaw, isNot(closeTo(yaw, 1e-6)));

    // Scrolling zooms.
    final distance = renderer.orbit.distance;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: origin + size.center(Offset.zero),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await settleGpu(tester, frames: 3);
    expect(renderer.orbit.distance, greaterThan(distance));

    expect(tester.takeException(), isNull);
    session.dispose();
    await engine.dispose();
  });
}
