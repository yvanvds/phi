import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/commands/command_palette.dart';
import 'package:phi/surfaces/midi/midi_viewport.dart';
import 'package:phi/surfaces/mix/mix_surface.dart';

import '../engine/test_doubles/fake_yse_gateway.dart';

/// Widget tests proving the default shortcut map is live in the real shell
/// (issue #255): the registry's [shortcutBindings] are what the workstation
/// binds, so pressing a default chord triggers its command, and the palette
/// shows the real chord on the matching row. Driven through [PhiApp] against a
/// [FakeYseGateway] — no `libyse.dll`, no GL.
void main() {
  Future<PhiEngine> pumpApp(WidgetTester tester, SessionState session) async {
    // A performance-sized window: the workstation chrome + a surface's header
    // strips need more than the 800x600 test default to lay out without
    // overflowing (this test drives the real app, not a widget in isolation).
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = PhiEngine(FakeYseGateway());
    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();
    return engine;
  }

  Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('Ctrl+5 focuses the MIDI surface through the registry', (
    tester,
  ) async {
    final session = SessionState();
    final engine = await pumpApp(tester, session);

    // App boots on Mix; MIDI is closed.
    expect(find.byType(MixSurface), findsOneWidget);
    expect(find.byType(MidiViewport), findsNothing);

    // Ctrl+5 is the 5th rail surface (MIDI). The chord runs the very same summon
    // path the rail tap and the palette row run.
    await pressCtrl(tester, LogicalKeyboardKey.digit5);
    expect(find.byType(MidiViewport), findsOneWidget);

    session.dispose();
    await engine.dispose();
  });

  testWidgets('F1 (aliased chord) opens the command palette', (tester) async {
    final session = SessionState();
    final engine = await pumpApp(tester, session);

    // F1 is registered as an alias of Ctrl+Shift+P on the one palette command —
    // proof an alias binds end-to-end through the registry, not just the primary.
    expect(find.byType(CommandPalette), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    session.dispose();
    await engine.dispose();
  });

  testWidgets('palette rows show the real chords (Go to MIDI → Ctrl+5)', (
    tester,
  ) async {
    final session = SessionState();
    final engine = await pumpApp(tester, session);

    // Open the palette with its own default chord, then filter to the MIDI
    // summon so its row is on screen.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byType(CommandPalette),
        matching: find.byType(TextField),
      ),
      'midi',
    );
    await tester.pumpAndSettle();

    // The registry-owned chord surfaces as the palette's discoverability story.
    expect(find.text('Go to MIDI'), findsOneWidget);
    expect(find.text('Ctrl+5'), findsOneWidget);

    session.dispose();
    await engine.dispose();
  });
}
