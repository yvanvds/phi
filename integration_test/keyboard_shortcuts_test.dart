import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/shell/shortcuts/keyboard_shortcuts_overlay.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the keyboard shortcuts overlay (issue #487), driven
/// through the real [PhiApp]: real rail navigation, the real focus tree with
/// the patcher canvas holding the keyboard, the registry's real Ctrl+/ binding
/// and real fonts and layout — backed by fakes, so no `libyse` is touched.
///
/// What only the composed app can answer: whether Ctrl+/ pressed while the
/// patcher canvas owns the keyboard bubbles past the canvas's own key handler
/// to the shell's bindings, whether the overlay reads the *layout's* focused
/// surface so the patcher's table leads, and whether the rail tooltips and the
/// empty-canvas hint show up in the real chrome.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('Ctrl+/ from the patcher lists the patcher first, with Ctrl+E', (
    tester,
  ) async {
    final engine = PhiEngine(
      FakeYseGateway(),
      patcherGateway: FakePatcherGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // The rail advertises the summon chord.
    expect(find.byTooltip('Patcher (Ctrl+2)'), findsOneWidget);

    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();
    // Give the canvas the keyboard, the way a performer would: a click on an
    // empty corner of it.
    final canvas = find.byType(PatcherCanvas);
    await tester.tapAt(tester.getBottomRight(canvas) - const Offset(20, 20));
    await tester.pumpAndSettle();

    await pressCtrl(tester, LogicalKeyboardKey.slash);
    final overlay = find.byType(KeyboardShortcutsOverlay);
    expect(overlay, findsOneWidget);

    // The focused surface's table leads, and Ctrl+E is in it — with the
    // tutorial caveat.
    final sections = tester.widget<KeyboardShortcutsOverlay>(overlay).sections;
    expect(sections.first.title, 'Patcher');
    expect(sections[1].title, 'Global');
    expect(
      find.descendant(of: overlay, matching: find.text('Ctrl+E')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: overlay,
        matching: find.text('unavailable while a tutorial is open'),
      ),
      findsOneWidget,
    );

    // The filter narrows to the matching rows.
    await tester.enterText(
      find.byKey(KeyboardShortcutsOverlay.fieldKey),
      'frame',
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: overlay, matching: find.text('Ctrl+0')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: overlay, matching: find.text('Ctrl+E')),
      findsNothing,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(overlay, findsNothing);

    // Empty the patch: the canvas now names the way in.
    final patcher = engine.patcher;
    expect(find.byKey(PatcherCanvas.emptyHintKey), findsNothing);
    patcher.selectNodes({for (final n in patcher.graph.nodes) n.id});
    patcher.deleteSelection();
    await tester.pumpAndSettle();
    expect(find.byKey(PatcherCanvas.emptyHintKey), findsOneWidget);
    expect(
      find.text(PatcherCanvas.emptyHintText.toUpperCase()),
      findsOneWidget,
    );

    session.dispose();
    await engine.dispose();
  });

  testWidgets('the palette entry "Keyboard Shortcuts" opens the overlay', (
    tester,
  ) async {
    final engine = PhiEngine(
      FakeYseGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'keyboard');
    await tester.pumpAndSettle();
    expect(find.text('Ctrl+/'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final overlay = find.byType(KeyboardShortcutsOverlay);
    expect(overlay, findsOneWidget);
    // Mix is focused at boot and has no local table, so Global leads.
    expect(
      tester.widget<KeyboardShortcutsOverlay>(overlay).sections.first.title,
      'Global',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    session.dispose();
    await engine.dispose();
  });
}
