import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/shell/commands/command_registry.dart';
import 'package:phi/shell/commands/command_shortcut.dart';
import 'package:phi/shell/commands/phi_command.dart';

/// Unit tests for the [CommandRegistry]: registration, enabled filtering,
/// invocation routing + recents tracking, and the default shortcut map that
/// issue #255 folds the app's bindings into.
void main() {
  PhiCommand cmd(
    String id, {
    String title = 'title',
    VoidCallback? invoke,
    bool Function()? isEnabled,
    CommandShortcut? shortcut,
  }) => PhiCommand(
    id: id,
    title: title,
    category: 'General',
    invoke: invoke ?? () {},
    isEnabled: isEnabled,
    shortcut: shortcut,
  );

  test('registers commands in order and looks them up by id', () {
    final registry = CommandRegistry();
    addTearDown(registry.dispose);

    registry.registerAll([cmd('a'), cmd('b')]);

    expect([for (final c in registry.commands) c.id], ['a', 'b']);
    expect(registry.byId('b')?.id, 'b');
    expect(registry.byId('missing'), isNull);
  });

  test('rejects a duplicate id', () {
    final registry = CommandRegistry();
    addTearDown(registry.dispose);
    registry.register(cmd('a'));
    expect(() => registry.register(cmd('a')), throwsArgumentError);
  });

  test('registering notifies listeners', () {
    final registry = CommandRegistry();
    addTearDown(registry.dispose);
    var notified = 0;
    registry.addListener(() => notified++);

    registry.register(cmd('a'));
    registry.registerAll([cmd('b'), cmd('c')]);

    expect(notified, 2); // one per register call, batched
  });

  test('enabledCommands hides commands whose predicate is false', () {
    final registry = CommandRegistry();
    addTearDown(registry.dispose);
    registry.registerAll([cmd('on'), cmd('off', isEnabled: () => false)]);

    expect([for (final c in registry.enabledCommands) c.id], ['on']);
  });

  test('invoke runs an enabled command and records it as most-recent', () {
    final registry = CommandRegistry();
    addTearDown(registry.dispose);
    var ran = 0;
    registry.registerAll([cmd('a', invoke: () => ran++), cmd('b')]);

    expect(registry.invoke('a'), isTrue);
    expect(ran, 1);
    expect(registry.recentIds, ['a']);

    registry.invoke('b');
    registry.invoke('a');
    // Newest first, each id appears once.
    expect(registry.recentIds, ['a', 'b']);
  });

  test('invoke is a no-op for an unknown or disabled command', () {
    final registry = CommandRegistry();
    addTearDown(registry.dispose);
    var ran = 0;
    registry.register(cmd('off', invoke: () => ran++, isEnabled: () => false));

    expect(registry.invoke('missing'), isFalse);
    expect(registry.invoke('off'), isFalse);
    expect(ran, 0);
    expect(registry.recentIds, isEmpty);
  });

  test('unregister removes a command and forgets its recency', () {
    final registry = CommandRegistry();
    addTearDown(registry.dispose);
    registry.registerAll([cmd('a'), cmd('b')]);
    registry.invoke('a');

    registry.unregister('a');

    expect(registry.byId('a'), isNull);
    expect([for (final c in registry.commands) c.id], ['b']);
    expect(registry.recentIds, isEmpty);
  });

  test('shortcutBindings maps advertised chords through invoke', () {
    final registry = CommandRegistry();
    addTearDown(registry.dispose);
    var ran = 0;
    registry.registerAll([
      cmd(
        'save',
        invoke: () => ran++,
        shortcut: const CommandShortcut(LogicalKeyboardKey.keyS, control: true),
      ),
      cmd('noShortcut'),
    ]);

    final bindings = registry.shortcutBindings();
    expect(bindings, hasLength(1)); // the command with no shortcut is skipped

    final binding = bindings.entries.single;
    final activator = binding.key as SingleActivator;
    expect(activator.trigger, LogicalKeyboardKey.keyS);
    expect(activator.control, isTrue);

    binding.value();
    expect(ran, 1);
    expect(registry.recentIds, ['save']); // firing the chord records recents
  });
}
