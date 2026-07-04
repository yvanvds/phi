import 'package:flutter/material.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_type.dart';

/// A modal yes/no confirmation styled to Phi's tokens — the guardrail in front
/// of a lossy or hard-to-undo action (e.g. the chain↔graph conversions in the
/// MIDI surface, issue #77).
///
/// Resolves to whether the performer confirmed: [show] coalesces a cancel or a
/// barrier-dismiss to `false`, so callers get a plain `bool`.
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    required this.title,
    required this.message,
    this.confirmLabel = 'continue',
    this.cancelLabel = 'cancel',
    super.key,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;

  /// Show the dialog over [context]; resolves to `true` iff the user confirmed.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'continue',
    String cancelLabel = 'cancel',
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PhiColors.bg1,
      title: Text(
        title,
        style: PhiType.caption().copyWith(color: PhiColors.fg1),
      ),
      content: Text(
        message,
        style: PhiType.monoS().copyWith(color: PhiColors.fg1),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
