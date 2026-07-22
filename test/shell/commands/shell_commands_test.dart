import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/shell/commands/command_registry.dart';
import 'package:phi/shell/commands/phi_command.dart';
import 'package:phi/shell/commands/shell_commands.dart';
import 'package:phi/shell/left_rail/surface_id.dart';

/// Unit tests for the shell's default shortcut map (issue #255): the chords the
/// workstation used to hard-wire are folded into [buildShellCommands] so the
/// registry is their single source of truth and the palette shows the real
/// chord on every row.
void main() {
  late SessionState session;
  late List<String> fired;

  List<PhiCommand> build() => buildShellCommands(
    session: session,
    onSummonSurface: (id) => fired.add('summon:${id.name}'),
    onUndo: () => fired.add('undo'),
    onRedo: () => fired.add('redo'),
    onCycleTabForward: () => fired.add('next'),
    onCycleTabBackward: () => fired.add('prev'),
    onOpenCommandPalette: () => fired.add('palette'),
    onPanic: () => fired.add('panic'),
    onSaveProject: () => fired.add('save'),
  );

  PhiCommand byId(List<PhiCommand> commands, String id) =>
      commands.firstWhere((c) => c.id == id);

  setUp(() {
    session = SessionState();
    fired = [];
  });

  tearDown(() => session.dispose());

  test('every rail surface gets Ctrl+<n> in rail order', () {
    final commands = build();
    // SurfaceId.values order is the rail order; Ctrl+1 lights the first icon.
    const expected = {
      SurfaceId.scene: '1',
      SurfaceId.patcher: '2',
      SurfaceId.code: '3',
      SurfaceId.state: '4',
      SurfaceId.midi: '5',
      SurfaceId.racks: '6',
      SurfaceId.mix: '7',
    };
    for (final entry in expected.entries) {
      final shortcut = byId(commands, 'surface.${entry.key.name}').shortcut!;
      expect(shortcut.control, isTrue);
      expect(shortcut.label, 'Ctrl+${entry.value}');
    }
  });

  test('folds the undo/redo, tab, and palette chords into the registry', () {
    final commands = build();

    expect(byId(commands, 'edit.undo').shortcut!.label, 'Ctrl+Z');

    final redo = byId(commands, 'edit.redo').shortcut!;
    expect(redo.label, 'Ctrl+Shift+Z');
    // Redo also owns the legacy Ctrl+Y as an alias — one command, two chords.
    expect(
      redo.activators,
      contains(const SingleActivator(LogicalKeyboardKey.keyY, control: true)),
    );

    expect(byId(commands, 'view.nextTab').shortcut!.label, 'Ctrl+Tab');
    expect(
      byId(commands, 'view.previousTab').shortcut!.label,
      'Ctrl+Shift+Tab',
    );

    final palette = byId(commands, 'view.commandPalette').shortcut!;
    expect(palette.label, 'Ctrl+Shift+P');
    // F1 is the aliased second opener.
    expect(
      palette.activators,
      contains(const SingleActivator(LogicalKeyboardKey.f1)),
    );

    expect(byId(commands, 'project.save').shortcut!.label, 'Ctrl+S');
  });

  test('the log toggle is a View command on Ctrl+J when wired', () {
    final commands = buildShellCommands(
      session: session,
      onSummonSurface: (id) => fired.add('summon:${id.name}'),
      onUndo: () => fired.add('undo'),
      onRedo: () => fired.add('redo'),
      onCycleTabForward: () => fired.add('next'),
      onCycleTabBackward: () => fired.add('prev'),
      onOpenCommandPalette: () => fired.add('palette'),
      onPanic: () => fired.add('panic'),
      onToggleLogPanel: () => fired.add('log'),
    );
    final log = byId(commands, 'view.log');
    expect(log.category, 'View');
    expect(log.shortcut!.label, 'Ctrl+J');
    log.invoke();
    expect(fired, ['log']);
  });

  test('the log toggle is omitted when no callback is wired', () {
    // The bare `build()` above passes no onToggleLogPanel — the command is
    // simply absent (like the project ops), so its chord claims nothing.
    expect(build().where((c) => c.id == 'view.log'), isEmpty);
  });

  test('panic is a permanent Transport command on F12', () {
    final commands = build();
    final panic = byId(commands, 'transport.panic');
    expect(panic.category, 'Transport');
    // Always enabled — panic is safe to run at any time (idempotent), unlike
    // play/stop which gate on the transport state.
    expect(panic.isEnabled, isTrue);
    expect(panic.shortcut!.label, 'F12');
    // Invoking it routes through the one `onPanic` callback the button shares.
    panic.invoke();
    expect(fired, ['panic']);
  });

  test('the assembled default map is conflict-free', () {
    final registry = CommandRegistry()..registerAll(build());
    addTearDown(registry.dispose);
    // Would throw (issue #255's debug conflict assertion) if any two defaults
    // claimed the same chord.
    final bindings = registry.shortcutBindings();

    // 7 surfaces + undo + redo(+Y) + nextTab + prevTab + palette(+F1) + panic(F12)
    // + save.
    expect(bindings, hasLength(7 + 1 + 2 + 1 + 1 + 2 + 1 + 1));
  });

  test('a folded-in chord routes through the same callback as the palette', () {
    final registry = CommandRegistry()..registerAll(build());
    addTearDown(registry.dispose);
    final bindings = registry.shortcutBindings();

    // Firing Ctrl+5 (MIDI) via the bound chord reaches the summon callback,
    // exactly as invoking the command from the palette would. Matched on the
    // trigger key because `SingleActivator` has only identity equality.
    SingleActivator activatorFor(LogicalKeyboardKey key) => bindings.keys
        .cast<SingleActivator>()
        .firstWhere((a) => a.trigger == key && a.control && !a.shift && !a.alt);

    bindings[activatorFor(LogicalKeyboardKey.digit5)]!();
    expect(fired, ['summon:midi']);
  });
}
