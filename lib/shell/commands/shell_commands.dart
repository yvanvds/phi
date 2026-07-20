import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../domain/session/session_state.dart';
import '../left_rail/surface_id.dart';
import 'command_shortcut.dart';
import 'phi_command.dart';

/// Ctrl+1 … Ctrl+7 focus the rail surfaces in rail order (design
/// `docs/design/shell-layout.md` §4, "surface focus"). Digit keys are chosen
/// deliberately for the performer's AZERTY layout: they are layout-*named*
/// logical keys, so `Ctrl+<n>` resolves the same everywhere — unlike
/// punctuation-position chords (`Ctrl+;`, `Ctrl+/`) whose physical key wanders
/// between AZERTY and QWERTY.
const List<LogicalKeyboardKey> _surfaceDigitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
];

/// Builds the shell's seed command set (design `docs/design/shell-layout.md`
/// §4): surface summon, edit (undo/redo), view (tab cycle, palette), transport,
/// projection, and — when the project stack is wired — project ops + settings.
///
/// Each command's `invoke` is the *same* callback the rail / toolbar / menu
/// already runs, so the palette is a launcher, never a second implementation.
/// The registry is the single source of truth for the app's default shortcut
/// map (issue #255): the chords that used to be hard-wired in the workstation's
/// `CallbackShortcuts` are folded in here as command [PhiCommand.shortcut]s, so
/// one table owns them and the palette shows the real chord on every row.
///
/// The project-op callbacks are nullable: they are `null` in the bare Phase-1
/// wiring (no project controller), and those commands are simply omitted.
List<PhiCommand> buildShellCommands({
  required SessionState session,
  required void Function(SurfaceId id) onSummonSurface,
  required VoidCallback onUndo,
  required VoidCallback onRedo,
  required VoidCallback onCycleTabForward,
  required VoidCallback onCycleTabBackward,
  required VoidCallback onOpenCommandPalette,
  VoidCallback? onNewProject,
  VoidCallback? onOpenProject,
  VoidCallback? onSaveProject,
  VoidCallback? onDuplicateProject,
  VoidCallback? onRenameProject,
  VoidCallback? onOpenSettings,
}) {
  return [
    // Surfaces — one summon per rail identity (design §4, "surface focus/summon"),
    // each bound to Ctrl+<n> in rail order.
    for (final (index, id) in SurfaceId.values.indexed)
      PhiCommand(
        id: 'surface.${id.name}',
        title: 'Go to ${id.label}',
        category: 'Surface',
        invoke: () => onSummonSurface(id),
        shortcut: index < _surfaceDigitKeys.length
            ? CommandShortcut(_surfaceDigitKeys[index], control: true)
            : null,
      ),
    // Edit — undo/redo follow the focused surface's stack (#119). Folded in from
    // the workstation's hard-wired Ctrl+Z / Ctrl+Shift+Z bindings; redo also
    // answers the legacy Ctrl+Y as an alias so the one command owns both chords.
    PhiCommand(
      id: 'edit.undo',
      title: 'Undo',
      category: 'Edit',
      invoke: onUndo,
      shortcut: const CommandShortcut(LogicalKeyboardKey.keyZ, control: true),
    ),
    PhiCommand(
      id: 'edit.redo',
      title: 'Redo',
      category: 'Edit',
      invoke: onRedo,
      shortcut: const CommandShortcut(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
        aliases: [SingleActivator(LogicalKeyboardKey.keyY, control: true)],
      ),
    ),
    // View — tab cycling in the focused pane (design §2) and the palette itself,
    // folded in from the workstation's hard-wired Ctrl+Tab / Ctrl+Shift+P
    // bindings. The palette also answers F1 as an alias.
    PhiCommand(
      id: 'view.nextTab',
      title: 'Next Tab',
      category: 'View',
      invoke: onCycleTabForward,
      shortcut: const CommandShortcut(LogicalKeyboardKey.tab, control: true),
    ),
    PhiCommand(
      id: 'view.previousTab',
      title: 'Previous Tab',
      category: 'View',
      invoke: onCycleTabBackward,
      shortcut: const CommandShortcut(
        LogicalKeyboardKey.tab,
        control: true,
        shift: true,
      ),
    ),
    PhiCommand(
      id: 'view.commandPalette',
      title: 'Command Palette…',
      category: 'View',
      invoke: onOpenCommandPalette,
      shortcut: const CommandShortcut(
        LogicalKeyboardKey.keyP,
        control: true,
        shift: true,
        aliases: [SingleActivator(LogicalKeyboardKey.f1)],
      ),
    ),
    // Transport — the same intents the toolbar's play/stop buttons drive. Their
    // enabled-predicates keep the palette honest: you can only play when stopped,
    // only stop when playing (a natural exercise of disabled-command hiding).
    PhiCommand(
      id: 'transport.play',
      title: 'Play',
      category: 'Transport',
      invoke: session.play,
      isEnabled: () => !session.isPlaying,
    ),
    PhiCommand(
      id: 'transport.stop',
      title: 'Stop',
      category: 'Transport',
      invoke: session.stop,
      isEnabled: () => session.isPlaying,
    ),
    PhiCommand(
      id: 'view.projection',
      title: 'Toggle Projection',
      category: 'View',
      invoke: session.toggleProjection,
    ),
    // Project ops — present only when the project stack is wired.
    if (onNewProject != null)
      PhiCommand(
        id: 'project.new',
        title: 'New Project',
        category: 'Project',
        invoke: onNewProject,
      ),
    if (onOpenProject != null)
      PhiCommand(
        id: 'project.open',
        title: 'Open Project…',
        category: 'Project',
        invoke: onOpenProject,
      ),
    if (onSaveProject != null)
      PhiCommand(
        id: 'project.save',
        title: 'Save Project',
        category: 'Project',
        invoke: onSaveProject,
        shortcut: const CommandShortcut(LogicalKeyboardKey.keyS, control: true),
      ),
    if (onDuplicateProject != null)
      PhiCommand(
        id: 'project.duplicate',
        title: 'Duplicate Project…',
        category: 'Project',
        invoke: onDuplicateProject,
      ),
    if (onRenameProject != null)
      PhiCommand(
        id: 'project.rename',
        title: 'Rename Project…',
        category: 'Project',
        invoke: onRenameProject,
      ),
    if (onOpenSettings != null)
      PhiCommand(
        id: 'app.settings',
        title: 'Settings…',
        category: 'App',
        invoke: onOpenSettings,
      ),
  ];
}
