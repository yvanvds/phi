import 'package:flutter/services.dart';

import '../../domain/session/session_state.dart';
import '../left_rail/surface_id.dart';
import 'command_shortcut.dart';
import 'phi_command.dart';

/// Builds the shell's seed command set (design `docs/design/shell-layout.md`
/// §4): surface summon, transport, projection, and — when the project stack is
/// wired — project ops + settings.
///
/// Each command's `invoke` is the *same* callback the rail / toolbar / menu
/// already runs, so the palette is a launcher, never a second implementation.
/// The project-op callbacks are nullable: they are `null` in the bare Phase-1
/// wiring (no project controller), and those commands are simply omitted.
List<PhiCommand> buildShellCommands({
  required SessionState session,
  required void Function(SurfaceId id) onSummonSurface,
  VoidCallback? onNewProject,
  VoidCallback? onOpenProject,
  VoidCallback? onSaveProject,
  VoidCallback? onDuplicateProject,
  VoidCallback? onRenameProject,
  VoidCallback? onOpenSettings,
}) {
  return [
    // Surfaces — one summon per rail identity (design §4, "surface focus/summon").
    for (final id in SurfaceId.values)
      PhiCommand(
        id: 'surface.${id.name}',
        title: 'Go to ${id.label}',
        category: 'Surface',
        invoke: () => onSummonSurface(id),
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
