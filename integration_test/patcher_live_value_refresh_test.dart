import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/fader/phi_fader.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/nodes/sine_node_body.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that the patcher's GUI bodies **follow the engine** — and
/// that they stop doing so the moment nobody is looking (issue #357).
///
/// A value arriving over a *cable* moves the native object and tells the Dart
/// side nothing, so every live body used to show whatever it last pushed
/// itself: the seeded `slider → ~sine` patch could be driven from a script or a
/// second editor and the canvas would sit there lying about it. This drives the
/// fake gateway's objects directly — the same thing a cable does, with nothing
/// said to the mirror — through the real [PhiApp]: real rail navigation, real
/// tab stack, real canvas layout, real fonts, no `libyse.dll`.
///
/// The gate is the half a widget test cannot reach at all: the shell keeps
/// background tabs *mounted*, so "is the patcher visible" is a property of the
/// composed workstation, and the only honest way to check that an offstage
/// patcher polls nothing is to put it offstage in the real shell.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  /// The frequency the `~sine` node prints on the canvas — reachable whether
  /// the Patcher is the foreground tab or parked behind another one.
  Finder freqReadout(String value) => find.descendant(
    of: find.byType(SineNodeBody, skipOffstage: false),
    matching: find.text(value, skipOffstage: false),
    skipOffstage: false,
  );

  testWidgets('cable-driven values reach the canvas, and stop arriving while '
      'the patcher is offstage', (tester) async {
    final patcherGateway = FakePatcherGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      patcherGateway: patcherGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    /// Land [value] on a seeded object the way the graph itself would — write
    /// the native object, tell Dart nothing. A logical node id mirrors the
    /// native handle the gateway keys its objects by.
    void driveFromEngine(PatchNodeId id, String value) =>
        patcherGateway.nodes[id.value]!.guiValue = value;

    /// Give the surface's poll time to come due, then let the frame it asks for
    /// land.
    Future<void> settlePoll() async {
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // Summon the Patcher surface, which seeds slider → sine → dac.
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    final sine = engine.patcher.graph.nodes.firstWhere(
      (n) => n.type == Obj.dSine,
    );
    final slider = engine.patcher.graph.nodes.firstWhere(
      (n) => n.type == Obj.gSlider,
    );
    expect(freqReadout('440'), findsOneWidget);
    expect(tester.widget<PhiFader>(find.byType(PhiFader)).value, 0.5);

    // 1) The graph moves on its own — nobody touches the canvas.
    driveFromEngine(sine.id, '660');
    driveFromEngine(slider.id, '0.8');
    await settlePoll();

    expect(freqReadout('660'), findsOneWidget);
    expect(freqReadout('440'), findsNothing);
    // The fader followed too: its thumb *and* its readout, from state the body
    // holds itself, not from a re-read on some unrelated rebuild.
    expect(tester.widget<PhiFader>(find.byType(PhiFader)).value, 0.8);
    expect(find.text('0.80'), findsOneWidget);

    // 2) Park the Patcher behind another surface. It stays mounted — its
    //    selection, pan and zoom survive a tab switch — but it must stop asking
    //    the engine anything at all.
    await tester.tap(railFor(SurfaceId.mix));
    await tester.pumpAndSettle();
    expect(find.byType(SineNodeBody, skipOffstage: false), findsOneWidget);

    driveFromEngine(sine.id, '880');
    await settlePoll();

    // Still showing what it showed when it went offstage: no poll ran behind
    // the Mix surface.
    expect(freqReadout('660'), findsOneWidget);
    expect(freqReadout('880'), findsNothing);

    // 3) Bring it back — the refresh resumes and the canvas catches up on its
    //    own, without the user touching a node.
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();
    await settlePoll();

    expect(freqReadout('880'), findsOneWidget);

    session.dispose();
    await engine.dispose();
  });
}
