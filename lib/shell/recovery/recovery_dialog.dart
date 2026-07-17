import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/project/recovery/recovery_offer.dart';

/// The launch-time recovery prompt (design `docs/design/project-registry.md`
/// §7, §9): when a project's journal holds commands the last save never
/// captured, this offers the three ways to treat them — replay everything,
/// replay all but the last edit, or discard the tail and open the clean save.
///
/// It renders a [RecoveryOffer] and resolves to the chosen [RecoveryChoice], or
/// `null` if the performer dismisses it (decide later). On a
/// [RecoveryOffer.crashLoop] — a prior recovery that never finished — it leads
/// with the warning and defaults focus to the safe *replay to previous* step, so
/// re-running the poison edit isn't the one-tap path.
///
/// Lives in the shell (workstation chrome) rather than the domain-agnostic
/// design layer because it reads a domain [RecoveryOffer]; the plain yes/no
/// `ConfirmDialog` stays in `design/` for reuse.
class RecoveryDialog extends StatelessWidget {
  /// Builds the dialog for [offer].
  const RecoveryDialog({required this.offer, super.key});

  /// What the launch inspection found in the journal.
  final RecoveryOffer offer;

  /// Shows the recovery dialog over [context] for [offer]; resolves to the
  /// performer's [RecoveryChoice], or `null` when dismissed.
  static Future<RecoveryChoice?> show(
    BuildContext context, {
    required RecoveryOffer offer,
  }) => showDialog<RecoveryChoice>(
    context: context,
    builder: (_) => RecoveryDialog(offer: offer),
  );

  String get _message {
    final n = offer.entryCount;
    final edits = n == 1 ? '1 unsaved edit' : '$n unsaved edits';
    if (offer.crashLoop) {
      return 'A previous recovery did not finish. The journal still holds '
          '$edits — the last one may be what crashed it. Replay to the '
          'previous step to skip it, or open the last clean save.';
    }
    return 'Phi closed unexpectedly with $edits not yet saved. Replay them '
        'onto the last save, or open the last clean save without them.';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PhiColors.bg1,
      title: Text(
        offer.crashLoop ? 'Recovery did not finish' : 'Recover unsaved work?',
        style: PhiType.caption().copyWith(color: PhiColors.fg1),
      ),
      content: Text(
        _message,
        style: PhiType.monoS().copyWith(color: PhiColors.fg1),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(RecoveryChoice.skipJournal),
          child: const Text('open last save'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(RecoveryChoice.replayToPrevious),
          child: const Text('replay to previous'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(RecoveryChoice.replayAll),
          child: const Text('replay all'),
        ),
      ],
    );
  }
}
