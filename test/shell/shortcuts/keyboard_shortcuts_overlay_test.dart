import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/shortcuts/shortcut_hint.dart';
import 'package:phi/domain/shortcuts/shortcut_hint_section.dart';
import 'package:phi/shell/shortcuts/keyboard_shortcuts_overlay.dart';

void main() {
  const sections = [
    ShortcutHintSection(
      title: 'Patcher',
      hints: [
        ShortcutHint(
          keys: ['Ctrl+E'],
          action: 'Toggle edit ↔ run mode',
          note: 'unavailable while a tutorial is open',
        ),
      ],
    ),
    ShortcutHintSection(
      title: 'Global',
      hints: [
        ShortcutHint(keys: ['Ctrl+Shift+Z', 'Ctrl+Y'], action: 'Redo'),
      ],
    ),
  ];

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () =>
                  KeyboardShortcutsOverlay.show(context, sections: sections),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders sections in order with chords, aliases and notes', (
    tester,
  ) async {
    await open(tester);
    expect(find.byType(KeyboardShortcutsOverlay), findsOneWidget);
    final patcher = tester.getTopLeft(find.text('PATCHER'));
    final global = tester.getTopLeft(find.text('GLOBAL'));
    expect(patcher.dy, lessThan(global.dy));
    expect(find.text('Ctrl+E'), findsOneWidget);
    expect(find.text('unavailable while a tutorial is open'), findsOneWidget);
    expect(find.text('Ctrl+Shift+Z'), findsOneWidget);
    expect(find.text('Ctrl+Y'), findsOneWidget);
  });

  testWidgets('the filter narrows the list, Esc closes', (tester) async {
    await open(tester);
    await tester.enterText(
      find.byKey(KeyboardShortcutsOverlay.fieldKey),
      'redo',
    );
    await tester.pumpAndSettle();
    expect(find.text('Redo'), findsOneWidget);
    expect(find.text('Ctrl+E'), findsNothing);
    expect(find.text('PATCHER'), findsNothing);

    await tester.enterText(
      find.byKey(KeyboardShortcutsOverlay.fieldKey),
      'qqqq',
    );
    await tester.pumpAndSettle();
    expect(find.text('No matching shortcuts'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(KeyboardShortcutsOverlay), findsNothing);
  });
}
