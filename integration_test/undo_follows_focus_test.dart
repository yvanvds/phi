import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/midi/piano_roll_editor.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of *undo follows focus* (issue #119): Ctrl+Z at the shell
/// level routes to the active surface's stack. An edit made on the MIDI surface
/// is not undone while another surface is active, and Ctrl+Z resumes undoing it
/// once MIDI is active again.
///
/// A [FakeMidiGateway] is wired so the shell sources the shared clip editor from
/// `engine.midi.editor` — the same editor the piano roll edits and whose scope
/// the shell registers — so the note count can be read directly regardless of
/// which surface is on-screen.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('Ctrl+Z routes to the focused surface only', (tester) async {
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // The engine starts as the app boots, so its MIDI editor — the same one the
    // shell registers as the MIDI undo scope — is available now.
    final editor = engine.midi.editor;

    Future<void> ctrlZ() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    Future<void> tapEmptyCell(double fx, double fy) async {
      final roll = tester.getRect(
        find.descendant(
          of: find.byType(PianoRollEditor),
          matching: find.byType(CustomPaint),
        ),
      );
      await tester.tapAt(
        Offset(roll.left + roll.width * fx, roll.top + roll.height * fy),
      );
      await tester.pumpAndSettle();
    }

    // Open MIDI; the seeded "phrase A" clip has 10 notes.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    expect(editor.clip.notes.length, 10);

    // Author a note past phrase A (right half of the roll) → one undoable edit.
    await tapEmptyCell(0.7, 0.5);
    expect(editor.clip.notes.length, 11);

    // Move focus to the Mix surface. The pending MIDI edit is now off-focus.
    await tester.tap(railFor(SurfaceId.mix));
    await tester.pumpAndSettle();

    // Ctrl+Z while Mix is active must NOT reach the MIDI stack — undo follows
    // focus, so the note stays put rather than being yanked from under Mix.
    await ctrlZ();
    expect(editor.clip.notes.length, 11);

    // Back on MIDI, author a second note (this also gives the roll focus) …
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    await tapEmptyCell(0.85, 0.3);
    expect(editor.clip.notes.length, 12);

    // … and now the same Ctrl+Z undoes it: the MIDI scope is focused again.
    await ctrlZ();
    expect(editor.clip.notes.length, 11);

    session.dispose();
    await engine.dispose();
  });
}
