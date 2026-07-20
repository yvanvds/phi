import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/commands/command_palette.dart';
import 'package:phi/surfaces/midi/midi_viewport.dart';
import 'package:phi/surfaces/mix/mix_surface.dart';

import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the command palette (issue #254, design
/// `docs/design/shell-layout.md` §4) driven through the real [PhiApp]: the
/// performer opens it with a keyboard shortcut, fuzzy-filters, and invokes a
/// command — which routes through the *same* code path as its rail/toolbar
/// equivalent (here summoning a surface and starting transport). All against
/// fakes — no `libyse.dll`, no GL.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder paletteField() => find.descendant(
    of: find.byType(CommandPalette),
    matching: find.byType(TextField),
  );

  Future<void> pressCtrlShiftP(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('Ctrl+Shift+P → filter → Enter summons the MIDI surface', (
    tester,
  ) async {
    final engine = PhiEngine(
      FakeYseGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // App boots on Mix; MIDI is closed.
    expect(find.byType(MixSurface), findsOneWidget);
    expect(find.byType(MidiViewport), findsNothing);

    // Open the palette with the real shortcut — it lists the seeded shell
    // commands (surface summon, transport, projection).
    await pressCtrlShiftP(tester);
    expect(find.byType(CommandPalette), findsOneWidget);
    expect(find.text('Go to MIDI'), findsOneWidget);

    // Fuzzy-filter to the MIDI summon and invoke it with Enter.
    await tester.enterText(paletteField(), 'midi');
    await tester.pumpAndSettle();
    expect(find.text('Go to MIDI'), findsOneWidget);
    expect(find.text('Go to Mix'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // The overlay closed and the MIDI surface is now onstage — the palette
    // reached the very same summon path the rail runs.
    expect(find.byType(CommandPalette), findsNothing);
    expect(find.byType(MidiViewport), findsOneWidget);

    session.dispose();
    await engine.dispose();
  });

  testWidgets('palette invokes transport play through the real session', (
    tester,
  ) async {
    final engine = PhiEngine(
      FakeYseGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();
    expect(session.isPlaying, isFalse);

    await pressCtrlShiftP(tester);
    await tester.enterText(paletteField(), 'play');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Play ran through session.play — the same intent the toolbar button drives.
    expect(session.isPlaying, isTrue);
    expect(find.byType(CommandPalette), findsNothing);

    // Reopen: Play is now disabled (can't play while playing) and hidden; Stop
    // has become enabled and shows — the enabled-predicate filtering, live.
    await pressCtrlShiftP(tester);
    expect(find.text('Play'), findsNothing);
    expect(find.text('Stop'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    session.dispose();
    await engine.dispose();
  });

  testWidgets('F1 also opens the palette', (tester) async {
    final engine = PhiEngine(
      FakeYseGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsNothing);

    session.dispose();
    await engine.dispose();
  });
}
