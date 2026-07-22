import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_type.dart';

/// The trigger-kind badge riding a transition curve's midpoint (design
/// `docs/design/state-graph.md` §5, issue #244): a small capsule naming what
/// fires the transition — MANUAL / CODE / TIMED / VARIABLE.
///
/// The badge is the transition's tap target: for a **manual** transition the
/// existing tap-to-arm gesture moves here (the canvas wires [onTap] to the
/// arm toggle), while every other kind opens the trigger editor. Armed
/// renders in the hot fuchsia palette to match the armed curve.
class StateTransitionBadge extends StatelessWidget {
  const StateTransitionBadge({
    required this.kind,
    this.armed = false,
    this.onTap,
    super.key,
  });

  /// The trigger's wire tag — "manual" / "code" / "timed" / "variable".
  final String kind;

  /// Whether the transition is armed — hot palette, matching the curve.
  final bool armed;

  /// Called on tap. `null` renders a non-interactive badge.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = armed ? PhiColors.live : PhiColors.fg2;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: PhiColors.bg2,
            borderRadius: PhiRadii.all2,
            border: Border.all(color: armed ? PhiColors.live : PhiColors.line2),
          ),
          child: Text(
            kind.toUpperCase(),
            style: PhiType.monoS().copyWith(
              fontSize: 8,
              letterSpacing: 0.08 * 8,
              color: accent,
            ),
          ),
        ),
      ),
    );
  }
}
