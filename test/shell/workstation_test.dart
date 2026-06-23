import 'package:flutter_test/flutter_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';

import '../engine/test_doubles/fake_scene_renderer.dart';
import '../engine/test_doubles/fake_yse_gateway.dart';

/// Widget tests for the workstation's Scene-visibility wiring (issue #18).
///
/// The Scene surface stays mounted in the [IndexedStack] across switches, so
/// the shell tells its [SceneRenderer] when Scene goes on- / off-stage. These
/// tests assert the `setVisible` signal tracks the selected surface, driving a
/// [FakeSceneRenderer] so no real 3D engine is touched.
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
}
