import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/project/lifecycle/project_controller.dart';
import '../../domain/project/lifecycle/project_directory_picker.dart';
import 'project_actions.dart';

/// The project menu in the top toolbar (design
/// `docs/design/project-registry.md` §9): New / Open / Open Recent / Save /
/// Duplicate / Rename, fronted by the current project's name.
///
/// A thin view over [ProjectActions] — it owns no lifecycle logic, only the menu
/// surface. Recents populate the "Open Recent" submenu live from
/// [ProjectController.recentProjects].
class ProjectMenu extends StatelessWidget {
  const ProjectMenu({
    required this.controller,
    required this.picker,
    this.onOpenSettings,
    super.key,
  });

  final ProjectController controller;
  final ProjectDirectoryPicker picker;

  /// Opens the settings dialog (design `settings-and-devices.md` §6). When set, a
  /// "Settings…" item joins the menu; `null` (the bare Phase-1 path) omits it.
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final actions = ProjectActions(controller: controller, picker: picker);
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          onPressed: () => unawaited(actions.newProject(context)),
          child: const Text('New'),
        ),
        MenuItemButton(
          onPressed: () => unawaited(actions.open(context)),
          child: const Text('Open…'),
        ),
        _recentSubmenu(context, actions),
        MenuItemButton(
          onPressed: () => unawaited(actions.save(context)),
          child: const Text('Save'),
        ),
        MenuItemButton(
          onPressed: () => unawaited(actions.duplicate(context)),
          child: const Text('Duplicate…'),
        ),
        MenuItemButton(
          onPressed: () => unawaited(actions.rename(context)),
          child: const Text('Rename…'),
        ),
        if (onOpenSettings != null)
          MenuItemButton(
            onPressed: onOpenSettings,
            child: const Text('Settings…'),
          ),
      ],
      builder: (context, menu, _) => _MenuTrigger(
        name: controller.name,
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }

  Widget _recentSubmenu(BuildContext context, ProjectActions actions) {
    // Pins float above recents and never age out (design §6). Listen to both
    // notifiers so a pin/remove in the settings dialog updates the menu at once.
    return ValueListenableBuilder<List<String>>(
      valueListenable: controller.pinnedProjects,
      builder: (context, pins, _) => ValueListenableBuilder<List<String>>(
        valueListenable: controller.recentProjects,
        builder: (context, recents, _) {
          final children = <Widget>[
            for (final path in pins)
              MenuItemButton(
                leadingIcon: const Icon(
                  Icons.push_pin,
                  size: 14,
                  color: PhiColors.fg2,
                ),
                onPressed: () => unawaited(actions.openRecent(context, path)),
                child: Text(p.basename(path)),
              ),
            if (pins.isNotEmpty && recents.isNotEmpty) const Divider(height: 1),
            for (final path in recents)
              MenuItemButton(
                onPressed: () => unawaited(actions.openRecent(context, path)),
                child: Text(p.basename(path)),
              ),
          ];
          return SubmenuButton(
            menuChildren: children.isEmpty
                ? const [
                    MenuItemButton(
                      onPressed: null,
                      child: Text('no recent projects'),
                    ),
                  ]
                : children,
            child: const Text('Open Recent'),
          );
        },
      ),
    );
  }
}

class _MenuTrigger extends StatelessWidget {
  const _MenuTrigger({required this.name, required this.onPressed});

  final ValueListenable<String> name;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: name,
      builder: (context, value, _) => TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.expand_more, size: 16, color: PhiColors.fg2),
        label: Text(
          value,
          style: PhiType.body().copyWith(color: PhiColors.fg0),
        ),
        style: TextButton.styleFrom(
          foregroundColor: PhiColors.fg0,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }
}
