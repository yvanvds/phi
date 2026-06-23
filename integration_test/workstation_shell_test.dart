import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/midi/midi_viewport.dart';
import 'package:phi/surfaces/midi/piano_roll_editor.dart';
import 'package:phi/surfaces/midi/velocity_lane.dart';

import '../test/engine/test_doubles/fake_scene_renderer.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end smoke test for the workstation shell.
///
/// Drives the real [PhiApp] (real navigation, fonts, layout) backed by a
/// [FakeYseGateway] so no native `libyse.dll` is touched. Exercises the
/// default Mix surface — add a channel, arm the engine test signal — then
/// switches surfaces through the left rail and back, asserting the
/// [IndexedStack] swaps the centre region and preserves engine state.
///
/// Replaces the original Phase-1 hello-world test (issue #48), which asserted
/// a `PLAY SINE` button + `PeakMeter` home screen that no longer exists.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('workstation: mix surface, rail switching, state preserved', (
    tester,
  ) async {
    final gateway = FakeYseGateway();
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // Shell chrome + default Mix surface are up. The Mix surface starts with
    // the master channel only (no user channels), so the header reads "1".
    expect(railFor(SurfaceId.mix), findsOneWidget);
    expect(railFor(SurfaceId.midi), findsOneWidget);
    expect(find.text('MIX · 1 CHANNELS'), findsOneWidget);
    expect(find.byType(MidiViewport), findsNothing);

    // Add a user channel via the header '+' button → count goes 1 → 2.
    await tester.tap(find.text('+'));
    await tester.pumpAndSettle();
    expect(find.text('MIX · 2 CHANNELS'), findsOneWidget);

    // Arm the engine's built-in test signal. The label is rendered uppercase
    // by PrimaryButton, so "play sine" → "PLAY SINE" / "STOP SINE".
    expect(find.text('PLAY SINE'), findsOneWidget);
    await tester.tap(find.text('PLAY SINE'));
    await tester.pumpAndSettle();
    expect(gateway.audioTestOn, isTrue);
    expect(engine.testSignal.value, isTrue);
    expect(find.text('STOP SINE'), findsOneWidget);

    // Switch to the MIDI surface via the left rail. The IndexedStack moves
    // the Mix surface offstage (its header is no longer found) and brings
    // the MIDI viewport onstage.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    expect(find.byType(MidiViewport), findsOneWidget);
    expect(find.text('MIX · 2 CHANNELS'), findsNothing);

    // Switch back to Mix. The added channel and the armed test signal are
    // both preserved — engine state outlives the surface swap.
    await tester.tap(railFor(SurfaceId.mix));
    await tester.pumpAndSettle();
    expect(find.text('MIX · 2 CHANNELS'), findsOneWidget);
    expect(find.text('STOP SINE'), findsOneWidget);
    expect(engine.testSignal.value, isTrue);

    session.dispose();
    await engine.dispose();
  });

  testWidgets('midi: add a note then undo it, end to end', (tester) async {
    final engine = PhiEngine(
      FakeYseGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // Navigate to the MIDI surface; the editor + velocity lane come up.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    expect(find.byType(PianoRollEditor), findsOneWidget);
    expect(find.byType(VelocityLane), findsOneWidget);

    // The seeded "phrase A" clip has 10 notes.
    expect(find.textContaining('10 notes'), findsOneWidget);

    // Tap an empty cell in the right half of the roll (past phrase A, which
    // sits in the first few beats) to author a new note.
    final roll = tester.getRect(
      find.descendant(
        of: find.byType(PianoRollEditor),
        matching: find.byType(CustomPaint),
      ),
    );
    await tester.tapAt(
      Offset(roll.left + roll.width * 0.7, roll.top + roll.height * 0.5),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('11 notes'), findsOneWidget);

    // The roll holds keyboard focus after the tap, so Ctrl+Z undoes the add.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.textContaining('10 notes'), findsOneWidget);

    session.dispose();
    await engine.dispose();
  });

  testWidgets('scene ticker pauses offstage, resumes when Scene selected', (
    tester,
  ) async {
    // Inject a fake renderer so the real left rail → workstation → renderer
    // visibility wiring (issue #18) is driven through the real app, without a
    // native 3D context. The macbear ticker itself can only run against a live
    // GL context, so this asserts the *signal*, which is what the shell owns.
    final renderer = FakeSceneRenderer();
    final engine = PhiEngine(
      FakeYseGateway(),
      sceneRenderer: renderer,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    List<String> visibility() =>
        renderer.calls.where((c) => c.startsWith('setVisible')).toList();

    // App opens on Mix → Scene is offstage from the start.
    expect(renderer.lastVisible, isFalse);
    expect(visibility(), ['setVisible:false']);

    // Select Scene → resume; leave for Mix → pause again.
    await tester.tap(railFor(SurfaceId.scene));
    await tester.pumpAndSettle();
    expect(renderer.lastVisible, isTrue);

    await tester.tap(railFor(SurfaceId.mix));
    await tester.pumpAndSettle();
    expect(renderer.lastVisible, isFalse);

    expect(visibility(), [
      'setVisible:false',
      'setVisible:true',
      'setVisible:false',
    ]);

    session.dispose();
    await engine.dispose();
  });
}
