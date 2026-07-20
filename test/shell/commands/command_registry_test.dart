import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/shell/commands/command_registry.dart';
import 'package:phi/shell/commands/command_shortcut.dart';
import 'package:phi/shell/commands/phi_command.dart';

/// Unit tests for the [CommandRegistry]: registration, enabled filtering,
/// invocation routing + recents tracking, and the default shortcut map that
/// issue #255 folds the app's bindings into.
/// Finds a bound callback by chord — `SingleActivator` has only identity
/// equality, so a binding map can't be probed with a fresh activator; match on
/// the trigger key (which *does* have value equality) plus the modifiers.
VoidCallback? _bindingFor(
  Map<ShortcutActivator, VoidCallback> bindings,
  LogicalKeyboardKey trigger, {
  bool control = false,
  bool shift = false,
  bool alt = false,
}) {
  for (final entry in bindings.entries) {
    final a = entry.key as SingleActivator;
    if (a.trigger == trigger &&
        a.control == control &&
        a.shift == shift &&
        a.alt == alt) {
      return entry.value;
    }
  }
  return null;
}

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

  test('shortcutBindings binds a chord and each of its aliases', () {
    final registry = CommandRegistry();
    addTearDown(registry.dispose);
    var ran = 0;
    registry.register(
      cmd(
        'redo',
        invoke: () => ran++,
        shortcut: const CommandShortcut(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
          aliases: [SingleActivator(LogicalKeyboardKey.keyY, control: true)],
        ),
      ),
    );

    final bindings = registry.shortcutBindings();
    // Primary Ctrl+Shift+Z and the aliased Ctrl+Y both map to the command.
    // (Looked up by trigger + modifiers because `SingleActivator` has no value
    // equality — a fresh instance never equals another of the same chord.)
    expect(bindings, hasLength(2));
    final primary = _bindingFor(
      bindings,
      LogicalKeyboardKey.keyZ,
      control: true,
      shift: true,
    );
    final alias = _bindingFor(bindings, LogicalKeyboardKey.keyY, control: true);
    expect(primary, isNotNull);
    expect(alias, isNotNull);

    // Firing either chord runs the one command.
    alias!();
    primary!();
    expect(ran, 2);
  });

  test('shortcutBindings asserts when two commands claim one chord', () {
    final registry = CommandRegistry();
    addTearDown(registry.dispose);
    registry.registerAll([
      cmd(
        'a',
        shortcut: const CommandShortcut(LogicalKeyboardKey.keyK, control: true),
      ),
      cmd(
        'b',
        shortcut: const CommandShortcut(LogicalKeyboardKey.keyK, control: true),
      ),
    ]);

    // The debug-build conflict assertion (issue #255) fails fast: a chord must
    // map to exactly one command. Asserts are enabled under `flutter test`.
    expect(registry.shortcutBindings, throwsA(isA<FlutterError>()));
  });

  test('shortcutBindings detects a conflict between a chord and an alias', () {
    final registry = CommandRegistry();
    addTearDown(registry.dispose);
    registry.registerAll([
      cmd(
        'primary',
        shortcut: const CommandShortcut(LogicalKeyboardKey.keyY, control: true),
      ),
      cmd(
        'aliased',
        shortcut: const CommandShortcut(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
          aliases: [SingleActivator(LogicalKeyboardKey.keyY, control: true)],
        ),
      ),
    ]);

    expect(registry.shortcutBindings, throwsA(isA<FlutterError>()));
  });
}
