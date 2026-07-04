import 'package:flutter_test/flutter_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/scene/scene_surface.dart';

import '../engine/test_doubles/fake_scene_renderer.dart';
import '../engine/test_doubles/fake_yse_gateway.dart';

/// Widget tests for the workstation's Scene-surface wiring.
///
/// Unlike the other surfaces (kept resident in the [IndexedStack]), Scene
/// mounts only while selected so macbear's `M3View` stays out of the tree when
/// offstage (issue #19). The shell also signals the renderer's on-/off-stage
/// state (issue #18). These tests assert both — the lazy mount/unmount and the
/// `setVisible` signal — driving a [FakeSceneRenderer] so no real 3D engine is
/// touched.
void main() {
  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  // The Scene viewport also seeds setCamera/setAgents on mount; isolate the
  // visibility signal so these assertions track only on-/off-stage changes.
  List<String> visibilityCalls(FakeSceneRenderer r) =>
      r.calls.where((c) => c.startsWith('setVisible')).toList();

  testWidgets('boots on Mix → Scene renderer starts offstage (paused)', (
    tester,
  ) async {
    final renderer = FakeSceneRenderer();
    final engine = PhiEngine(FakeYseGateway(), sceneRenderer: renderer);
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // start() initialises the renderer; the shell then parks it offstage
    // because the app opens on Mix, not Scene.
    expect(renderer.calls, contains('init'));
    expect(visibilityCalls(renderer), ['setVisible:false']);
    expect(renderer.lastVisible, isFalse);

    session.dispose();
    await engine.dispose();
  });

  testWidgets('selecting Scene resumes; leaving it pauses again', (
    tester,
  ) async {
    final renderer = FakeSceneRenderer();
    final engine = PhiEngine(FakeYseGateway(), sceneRenderer: renderer);
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // Mix → Scene → Mix round-trip.
    await tester.tap(railFor(SurfaceId.scene));
    await tester.pumpAndSettle();
    expect(renderer.lastVisible, isTrue);

    await tester.tap(railFor(SurfaceId.mix));
    await tester.pumpAndSettle();
    expect(renderer.lastVisible, isFalse);

    expect(visibilityCalls(renderer), [
      'setVisible:false',
      'setVisible:true',
      'setVisible:false',
    ]);

    session.dispose();
    await engine.dispose();
  });

  testWidgets('Scene view mounts only while Scene is selected (issue #19)', (
    tester,
  ) async {
    final renderer = FakeSceneRenderer();
    final engine = PhiEngine(FakeYseGateway(), sceneRenderer: renderer);
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // App boots on Mix → the Scene surface (and macbear's M3View) never entered
    // the tree, so ANGLE init stays off the boot path.
    expect(find.byType(SceneSurface), findsNothing);
    expect(renderer.viewMounted, isFalse);
    expect(renderer.viewMounts, 0);

    // Select Scene → the surface and the renderer's view mount.
    await tester.tap(railFor(SurfaceId.scene));
    await tester.pumpAndSettle();
    expect(find.byType(SceneSurface), findsOneWidget);
    expect(renderer.viewMounted, isTrue);
    expect(renderer.viewMounts, 1);

    // Leave Scene → both unmount (the fork keeps M3AppEngine warm underneath).
    await tester.tap(railFor(SurfaceId.mix));
    await tester.pumpAndSettle();
    expect(find.byType(SceneSurface), findsNothing);
    expect(renderer.viewMounted, isFalse);
    expect(renderer.viewDisposes, 1);

    // Re-enter Scene → a fresh view attaches without crashing (the regression
    // this issue fixes hit on the second mount).
    await tester.tap(railFor(SurfaceId.scene));
    await tester.pumpAndSettle();
    expect(find.byType(SceneSurface), findsOneWidget);
    expect(renderer.viewMounted, isTrue);
    expect(renderer.viewMounts, 2);
    expect(tester.takeException(), isNull);

    session.dispose();
    await engine.dispose();
  });
}
