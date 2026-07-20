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

/// End-to-end proof of the default shortcut map (issue #255, design
/// `docs/design/shell-layout.md` §4) driven through the real [PhiApp]: the
/// chords the workstation used to hard-wire are now owned by the command
/// registry, so pressing a default chord runs the *same* code path as its
/// rail/palette equivalent, and the palette advertises the real chord on every
/// row. All against fakes — no `libyse.dll`, no GL.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder paletteField() => find.descendant(
    of: find.byType(CommandPalette),
    matching: find.byType(TextField),
  );

  Future<void> pressCtrlDigit(
    WidgetTester tester,
    LogicalKeyboardKey digit,
  ) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(digit);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('Ctrl+5 summons the MIDI surface via the registry-owned chord', (
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

    // Ctrl+5 is the 5th rail identity (MIDI) — the summon path the rail runs.
    await pressCtrlDigit(tester, LogicalKeyboardKey.digit5);
    expect(find.byType(MidiViewport), findsOneWidget);

    session.dispose();
    await engine.dispose();
  });

  testWidgets('the palette advertises the real chord on the surface row', (
    tester,
  ) async {
    final engine = PhiEngine(
      FakeYseGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // Open the palette with its own default chord (Ctrl+Shift+P).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsOneWidget);

    await tester.enterText(paletteField(), 'midi');
    await tester.pumpAndSettle();

    // The registry is the single source of truth, so the chord it binds is the
    // chord the palette shows — discoverability, for free.
    expect(find.text('Go to MIDI'), findsOneWidget);
    expect(find.text('Ctrl+5'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    session.dispose();
    await engine.dispose();
  });
}
