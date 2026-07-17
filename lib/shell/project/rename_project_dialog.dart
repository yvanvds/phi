import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_type.dart';

/// A one-field dialog that asks for a new project name — the "rename" menu
/// action (design `docs/design/project-registry.md` §9).
///
/// Resolves to the trimmed name the performer entered, or `null` if they
/// cancelled or left it blank. Submitting the field (Enter) is equivalent to
/// pressing "rename".
class RenameProjectDialog extends StatefulWidget {
  const RenameProjectDialog({required this.initialName, super.key});

  /// The project's current name, pre-filled and selected for quick replacement.
  final String initialName;

  /// Shows the dialog over [context]; resolves to the new name or `null`.
  static Future<String?> show(
    BuildContext context, {
    required String initialName,
  }) => showDialog<String>(
    context: context,
    builder: (_) => RenameProjectDialog(initialName: initialName),
  );

  @override
  State<RenameProjectDialog> createState() => _RenameProjectDialogState();
}

class _RenameProjectDialogState extends State<RenameProjectDialog> {
  late final TextEditingController _field = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _field.text.trim();
    Navigator.of(context).pop(name.isEmpty ? null : name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PhiColors.bg1,
      title: Text(
        'Rename project',
        style: PhiType.caption().copyWith(color: PhiColors.fg1),
      ),
      content: TextField(
        controller: _field,
        autofocus: true,
        style: PhiType.monoS().copyWith(color: PhiColors.fg0),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('rename')),
      ],
    );
  }
}
