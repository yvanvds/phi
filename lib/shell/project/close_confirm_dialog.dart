import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_type.dart';
import 'close_decision.dart';

/// The confirm-on-close prompt (design `docs/design/project-registry.md` §9):
/// shown when the app is asked to exit with unsaved changes, it offers to save,
/// discard, or stay. Unlike the plain yes/no `ConfirmDialog`, closing has three
/// outcomes, so it resolves to a [CloseDecision].
///
/// A barrier dismiss coalesces to [CloseDecision.cancel] — the safe choice that
/// keeps the unsaved work.
class CloseConfirmDialog extends StatelessWidget {
  const CloseConfirmDialog({super.key});

  /// Shows the dialog over [context]; resolves to the performer's
  /// [CloseDecision] ([CloseDecision.cancel] on a barrier dismiss).
  static Future<CloseDecision> show(BuildContext context) async {
    final decision = await showDialog<CloseDecision>(
      context: context,
      builder: (_) => const CloseConfirmDialog(),
    );
    return decision ?? CloseDecision.cancel;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PhiColors.bg1,
      title: Text(
        'Unsaved changes',
        style: PhiType.caption().copyWith(color: PhiColors.fg1),
      ),
      content: Text(
        'This project has changes that have not been saved. Save them before '
        'closing, discard them, or keep working?',
        style: PhiType.monoS().copyWith(color: PhiColors.fg1),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(CloseDecision.cancel),
          child: const Text('keep working'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(CloseDecision.discard),
          child: const Text('discard'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(CloseDecision.save),
          child: const Text('save'),
        ),
      ],
    );
  }
}
