import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import 'log_panel_controller.dart';

/// The status-bar log toggle (design `docs/design/diagnostics.md` §4, §5): a
/// compact button that opens/closes the log drawer and **badges the count of
/// error entries since the drawer was last open**.
///
/// With a badge showing, a tap opens the drawer *filtered to errors* and clears
/// the badge (design §5); with no badge it just toggles the drawer. Lit while
/// the drawer is open. The palette command and `Ctrl+J` share the plain toggle
/// path, so this button is never a second implementation of "open the log".
class LogPanelToggle extends StatelessWidget {
  /// Watches [controller] for the open state and the badge count.
  const LogPanelToggle({required this.controller, super.key});

  /// The panel controller — its open state and unseen-error count drive the look.
  final LogPanelController controller;

  /// Keys tests target the toggle and its badge by.
  static const Key toggleKey = Key('BottomStatus.logToggle');
  static const Key badgeKey = Key('BottomStatus.logToggle.badge');

  void _onTap() {
    if (controller.hasUnseenErrors) {
      controller.openFilteredToErrors();
    } else {
      controller.toggle();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final open = controller.isOpen;
        final errors = controller.unseenErrorCount;
        return Tooltip(
          message: errors > 0
              ? '$errors error${errors == 1 ? '' : 's'} — open the log filtered to errors'
              : 'toggle the log (Ctrl+J)',
          child: GestureDetector(
            key: toggleKey,
            behavior: HitTestBehavior.opaque,
            onTap: _onTap,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s2),
                decoration: BoxDecoration(
                  color: open
                      ? PhiColors.voice1.withValues(alpha: 0.16)
                      : PhiColors.bg2,
                  borderRadius: PhiRadii.allPill,
                  border: Border.all(
                    color: open ? PhiColors.voice1 : PhiColors.line1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.terminal,
                      size: 12,
                      color: open ? PhiColors.voice1 : PhiColors.fg2,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'LOG',
                      style: PhiType.caption().copyWith(
                        color: open ? PhiColors.voice1 : PhiColors.fg2,
                      ),
                    ),
                    if (errors > 0) ...[
                      const SizedBox(width: PhiSpacing.s1),
                      _Badge(count: errors),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The red error-count pill on the toggle.
class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: LogPanelToggle.badgeKey,
      constraints: const BoxConstraints(minWidth: 14),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: const BoxDecoration(
        color: PhiColors.hot,
        borderRadius: PhiRadii.allPill,
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: PhiType.monoS().copyWith(
          color: PhiColors.bg0,
          fontWeight: FontWeight.w700,
          fontSize: 9,
        ),
      ),
    );
  }
}
