import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';

/// The panic button in the bottom status strip (issue #264, design
/// `docs/design/midi-recording.md` §6): the one unmissable, mashable
/// stop-everything, sitting right of the `LIVE` dot.
///
/// Tapping it runs [onPanic] — the workstation routes that to
/// `PhiEngine.panic`, the very same action the palette command and the permanent
/// shortcut fire (a button is never a second implementation). Tinted with the
/// `hot` danger colour so it reads as an emergency control, never mistaken for
/// ordinary transport.
class PanicButton extends StatelessWidget {
  const PanicButton({required this.onPanic, super.key});

  /// Runs the panic action. Wired to `PhiEngine.panic` in the workstation; a
  /// widget test passes a spy to prove the button reaches it.
  final VoidCallback onPanic;

  /// Key so tests (and the end-to-end flow) can target the button unambiguously.
  static const Key buttonKey = Key('BottomStatus.panic');

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'panic — stop everything, all notes off',
      child: GestureDetector(
        key: buttonKey,
        behavior: HitTestBehavior.opaque,
        onTap: onPanic,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s2),
            decoration: BoxDecoration(
              color: PhiColors.hot.withValues(alpha: 0.16),
              borderRadius: PhiRadii.allPill,
              border: Border.all(color: PhiColors.hot),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 12,
                  color: PhiColors.hot,
                ),
                const SizedBox(width: 3),
                Text(
                  'PANIC',
                  style: PhiType.caption().copyWith(
                    color: PhiColors.hot,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
