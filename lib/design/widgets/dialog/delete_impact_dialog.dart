import 'package:flutter/material.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_spacing.dart';
import '../../tokens/phi_type.dart';

/// The **delete-impact** warning — the guardrail a surface raises before it
/// removes a node that others still reference (design
/// `docs/design/project-registry.md` §4; `docs/design/mix.md` §4 for the mix
/// case: a return bus with active senders).
///
/// String-based on purpose, so the design layer stays free of domain types: the
/// surface maps the registry's `DeleteImpact` (its target + referrer addresses)
/// into [message] + [referrers] before showing this. [show] coalesces a cancel
/// or a barrier-dismiss to `false`, so callers get a plain `bool` — `true` only
/// when the performer confirmed the delete.
class DeleteImpactDialog extends StatelessWidget {
  const DeleteImpactDialog({
    required this.title,
    required this.message,
    required this.referrers,
    this.confirmLabel = 'delete',
    this.cancelLabel = 'cancel',
    super.key,
  });

  final String title;

  /// The lead line above the referrer list (e.g. "verb still receives these
  /// sends. Deleting it clears them:").
  final String message;

  /// The referents left dangling — one label per line (an address in its dotted
  /// form). Never empty when this dialog is shown; a safe delete skips it.
  final List<String> referrers;

  final String confirmLabel;
  final String cancelLabel;

  /// Show the dialog over [context]; resolves to `true` iff the performer
  /// confirmed the delete.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    required List<String> referrers,
    String confirmLabel = 'delete',
    String cancelLabel = 'cancel',
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => DeleteImpactDialog(
        title: title,
        message: message,
        referrers: referrers,
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
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: PhiType.monoS().copyWith(color: PhiColors.fg1)),
          const SizedBox(height: PhiSpacing.s2),
          for (final referrer in referrers)
            Padding(
              padding: const EdgeInsets.only(bottom: PhiSpacing.s0),
              child: Text(
                '• $referrer',
                style: PhiType.monoS().copyWith(color: PhiColors.fg2),
              ),
            ),
        ],
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
