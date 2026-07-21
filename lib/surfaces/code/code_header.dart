import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/toggle/phi_toggle.dart';

/// Header bar of the Code surface (design `docs/design/live-coding.md` §5, §8
/// decision 3, issue #232). Carries the `fresh` toggle and a visible mode
/// indicator so replace-mode is never ambient state the performer forgot.
///
/// Layering is the default (`fresh` off): each evaluation adds to the running
/// namespace. Turning `fresh` on prefixes every evaluation with
/// `yse.cancel_all()`, so a block replaces what was scheduled rather than
/// stacking on it — the mode indicator lights fuchsia to signal it.
class CodeHeader extends StatelessWidget {
  const CodeHeader({required this.fresh, super.key});

  /// The live `fresh` flag — toggled here, read by the editor when it builds
  /// the source it submits.
  final ValueNotifier<bool> fresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: const BoxDecoration(
        color: PhiColors.bg1,
        border: Border(bottom: BorderSide(color: PhiColors.line1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s3),
      child: ValueListenableBuilder<bool>(
        valueListenable: fresh,
        builder: (context, on, _) {
          return Row(
            children: [
              Text('fresh', style: PhiType.caption()),
              const SizedBox(width: PhiSpacing.s2),
              PhiToggle(value: on, onChanged: (v) => fresh.value = v),
              const SizedBox(width: PhiSpacing.s3),
              _ModeIndicator(fresh: on),
            ],
          );
        },
      ),
    );
  }
}

/// The always-visible mode label — `replace · yse.cancel_all()` in fuchsia when
/// `fresh` is on, a subdued `layer` when off.
class _ModeIndicator extends StatelessWidget {
  const _ModeIndicator({required this.fresh});

  final bool fresh;

  @override
  Widget build(BuildContext context) {
    if (!fresh) {
      return Text(
        'layer',
        style: PhiType.monoS().copyWith(color: PhiColors.fg3),
      );
    }
    return Text(
      'replace · yse.cancel_all()',
      style: PhiType.monoS().copyWith(color: PhiColors.voice1),
    );
  }
}
