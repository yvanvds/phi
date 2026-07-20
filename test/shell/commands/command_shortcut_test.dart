import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/shell/commands/command_shortcut.dart';

/// Unit tests for [CommandShortcut]: the display label the palette renders and
/// the [SingleActivator] the shell binds (issue #255).
void main() {
  test('renders modifiers then the trigger label', () {
    const shortcut = CommandShortcut(
      LogicalKeyboardKey.keyP,
      control: true,
      shift: true,
    );
    expect(shortcut.label, 'Ctrl+Shift+P');
  });

  test('a bare key renders just its label', () {
    const shortcut = CommandShortcut(LogicalKeyboardKey.keyS);
    expect(shortcut.label, 'S');
  });

  test('names control keys that carry no printable label', () {
    expect(const CommandShortcut(LogicalKeyboardKey.f1).label, 'F1');
    expect(const CommandShortcut(LogicalKeyboardKey.escape).label, 'Esc');
  });

  test('an explicit trigger label overrides the derived one', () {
    const shortcut = CommandShortcut(
      LogicalKeyboardKey.f1,
      triggerLabel: 'Help',
    );
    expect(shortcut.label, 'Help');
  });

  test('builds a matching SingleActivator', () {
    const shortcut = CommandShortcut(LogicalKeyboardKey.keyS, control: true);
    // SingleActivator matches key events via `accepts()` rather than value
    // equality, so assert its fields instead of comparing instances.
    final activator = shortcut.activator;
    expect(activator.trigger, LogicalKeyboardKey.keyS);
    expect(activator.control, isTrue);
    expect(activator.shift, isFalse);
    expect(activator.alt, isFalse);
  });

  test('value equality over trigger + modifiers', () {
    const a = CommandShortcut(LogicalKeyboardKey.keyP, control: true);
    const b = CommandShortcut(LogicalKeyboardKey.keyP, control: true);
    const c = CommandShortcut(LogicalKeyboardKey.keyP, shift: true);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });
}
