import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/shell/commands/command_palette.dart';
import 'package:phi/shell/commands/command_registry.dart';
import 'package:phi/shell/commands/command_shortcut.dart';
import 'package:phi/shell/commands/phi_command.dart';

/// Widget tests for the command palette overlay (design
/// `docs/design/shell-layout.md` §4): opening, fuzzy filtering, disabled
/// commands hidden, shortcut rendering, keyboard navigation + Enter, and
/// tap-to-invoke — each execution reaching the fake action and closing the
/// overlay.
void main() {
  late List<String> invoked;
  late CommandRegistry registry;

  PhiCommand cmd(
    String id,
    String title, {
    String category = 'Surface',
    bool Function()? isEnabled,
    CommandShortcut? shortcut,
  }) => PhiCommand(
    id: id,
    title: title,
    category: category,
    invoke: () => invoked.add(id),
    isEnabled: isEnabled,
    shortcut: shortcut,
  );

  setUp(() {
    invoked = [];
    registry = CommandRegistry()
      ..registerAll([
        cmd('surface.mix', 'Go to Mix'),
        cmd('surface.midi', 'Go to MIDI'),
        cmd('transport.play', 'Play', category: 'Transport'),
        cmd(
          'transport.stop',
          'Stop',
          category: 'Transport',
          isEnabled: () => false,
        ),
        cmd(
          'project.save',
          'Save Project',
          category: 'Project',
          shortcut: const CommandShortcut(
            LogicalKeyboardKey.keyS,
            control: true,
          ),
        ),
      ]);
  });

  tearDown(() => registry.dispose());

  Future<void> openPalette(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () =>
                    CommandPalette.show(context, registry: registry),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens with all enabled commands, disabled ones hidden', (
    tester,
  ) async {
    await openPalette(tester);

    expect(find.byType(CommandPalette), findsOneWidget);
    expect(find.text('Go to Mix'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    // The disabled Stop command never renders (design §4).
    expect(find.text('Stop'), findsNothing);
  });

  testWidgets('renders a command\'s shortcut chord on its row', (tester) async {
    await openPalette(tester);
    expect(find.text('Ctrl+S'), findsOneWidget);
  });

  testWidgets('filters commands by fuzzy query', (tester) async {
    await openPalette(tester);

    await tester.enterText(find.byType(TextField), 'midi');
    await tester.pumpAndSettle();

    expect(find.text('Go to MIDI'), findsOneWidget);
    expect(find.text('Go to Mix'), findsNothing);
    expect(find.text('Play'), findsNothing);
  });

  testWidgets('shows an empty state when nothing matches', (tester) async {
    await openPalette(tester);
    await tester.enterText(find.byType(TextField), 'zzzzz');
    await tester.pumpAndSettle();
    expect(find.text('No matching commands'), findsOneWidget);
  });

  testWidgets('Enter invokes the highlighted command and closes', (
    tester,
  ) async {
    await openPalette(tester);

    // Narrow to the single Save command, then invoke it with Enter.
    await tester.enterText(find.byType(TextField), 'save');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(invoked, ['project.save']);
    expect(find.byType(CommandPalette), findsNothing); // overlay popped
    expect(registry.recentIds, ['project.save']); // recorded as recent
  });

  testWidgets('ArrowDown moves the highlight before Enter invokes', (
    tester,
  ) async {
    await openPalette(tester);

    // Empty query → registration order: Go to Mix, Go to MIDI, Play, Save.
    // One ArrowDown selects the second row (Go to MIDI).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(invoked, ['surface.midi']);
  });

  testWidgets('Escape closes without invoking', (tester) async {
    await openPalette(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(CommandPalette), findsNothing);
    expect(invoked, isEmpty);
  });

  testWidgets('tapping a row invokes that command', (tester) async {
    await openPalette(tester);

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(invoked, ['transport.play']);
    expect(find.byType(CommandPalette), findsNothing);
  });

  testWidgets('recently-used commands float to the top on reopen', (
    tester,
  ) async {
    await openPalette(tester);
    await tester.tap(find.text('Save Project'));
    await tester.pumpAndSettle();

    // Reopen: Save Project is now the first row (recents first, design §4).
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final firstTitle = tester
        .widgetList<Text>(find.byType(Text))
        .firstWhere((t) => t.data == 'Save Project');
    expect(firstTitle.data, 'Save Project');
    // And it is at the top: its position is above the other command rows.
    final saveTop = tester.getTopLeft(find.text('Save Project')).dy;
    final mixTop = tester.getTopLeft(find.text('Go to Mix')).dy;
    expect(saveTop, lessThan(mixTop));
  });
}
