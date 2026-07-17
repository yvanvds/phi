import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/dialog/confirm_dialog.dart';
import '../../domain/project/lifecycle/project_controller.dart';
import '../../domain/project/lifecycle/project_directory_picker.dart';
import '../../domain/project/recovery/recovery_offer.dart';
import '../recovery/recovery_dialog.dart';
import 'rename_project_dialog.dart';

/// The project-lifecycle menu actions (design
/// `docs/design/project-registry.md` §9), orchestrating the [ProjectController],
/// the folder [ProjectDirectoryPicker], and the confirm/recovery/rename dialogs.
///
/// Shared by the toolbar's `ProjectMenu` and the shell's Ctrl+S shortcut so the
/// save-or-choose-location logic lives in exactly one place. Every method that
/// switches away from the open project first confirms discarding unsaved work.
class ProjectActions {
  const ProjectActions({required this.controller, required this.picker});

  final ProjectController controller;
  final ProjectDirectoryPicker picker;

  /// Starts a fresh project, confirming first if the current one is dirty.
  Future<void> newProject(BuildContext context) async {
    if (!await _confirmDiscard(context)) return;
    controller.newProject();
  }

  /// Picks an existing `.phi` folder and opens it (with recovery if its journal
  /// is dirty), confirming first if the current project is dirty.
  Future<void> open(BuildContext context) async {
    if (!await _confirmDiscard(context)) return;
    final path = await picker.pickProjectToOpen();
    if (path == null || !context.mounted) return;
    await _openPath(context, path);
  }

  /// Opens a known recent project [path], confirming discard first.
  Future<void> openRecent(BuildContext context, String path) async {
    if (!await _confirmDiscard(context)) return;
    if (!context.mounted) return;
    await _openPath(context, path);
  }

  /// Saves the open project — straight to disk when it already has a home, else
  /// prompting for a location first (design §9, Save on a new project).
  Future<void> save(BuildContext context) async {
    if (controller.isSaved) {
      await controller.save();
      return;
    }
    await _saveToNewLocation(context);
  }

  /// Writes a portable copy of the project to a chosen location and continues
  /// working there — the "Duplicate Project" action (design §9).
  Future<void> duplicate(BuildContext context) => _saveToNewLocation(context);

  /// Prompts for a new project name and applies it.
  Future<void> rename(BuildContext context) async {
    final name = await RenameProjectDialog.show(
      context,
      initialName: controller.name.value,
    );
    if (name == null) return;
    controller.renameProject(name);
  }

  Future<void> _openPath(BuildContext context, String path) async {
    try {
      await controller.open(path, prompt: _recoveryPrompt(context));
    } on Object catch (_) {
      controller.forgetRecent(path);
      if (context.mounted) {
        await _showError(context, 'Could not open the project at\n$path');
      }
    }
  }

  Future<void> _saveToNewLocation(BuildContext context) async {
    final path = await picker.pickNewProjectLocation(
      suggestedName: controller.name.value,
    );
    if (path == null) return;
    await controller.saveAs(path);
  }

  RecoveryPrompt _recoveryPrompt(BuildContext context) =>
      (RecoveryOffer offer) async {
        if (!context.mounted) return null;
        return RecoveryDialog.show(context, offer: offer);
      };

  Future<bool> _confirmDiscard(BuildContext context) async {
    if (!controller.isDirty.value) return true;
    return ConfirmDialog.show(
      context,
      title: 'Discard unsaved changes?',
      message:
          'The open project has changes that have not been saved. '
          'Continue and lose them?',
      confirmLabel: 'discard',
    );
  }

  Future<void> _showError(BuildContext context, String message) => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: PhiColors.bg1,
      title: Text(
        'Open failed',
        style: PhiType.caption().copyWith(color: PhiColors.fg1),
      ),
      content: Text(
        message,
        style: PhiType.monoS().copyWith(color: PhiColors.fg1),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ok'),
        ),
      ],
    ),
  );
}
