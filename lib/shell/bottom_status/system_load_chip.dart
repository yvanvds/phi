import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/system_load/system_load.dart';
import '../../domain/system_load/system_load_level.dart';
import 'system_load_colours.dart';
import 'system_load_popover.dart';

/// The status bar's `SYS` chip (issue #24): a dot coloured by the busiest
/// thread of the Phi process — green with headroom, amber past 60 % of a core,
/// red past 85 % — beside `CPU`, which keeps showing the audio-callback budget.
///
/// Clicking it opens the [SystemLoadPopover] above the strip with the busiest
/// threads by name; it stays live while open and an outside click closes it.
class SystemLoadChip extends StatefulWidget {
  /// Watches [load] (published by the shell's `SystemLoadMonitor`).
  const SystemLoadChip({required this.load, super.key});

  final ValueListenable<SystemLoad> load;

  static const Key chipKey = Key('BottomStatus.sysChip');
  static const Key dotKey = Key('BottomStatus.sysDot');

  /// The hover text for [load] — also what tests assert on.
  @visibleForTesting
  static String tooltipFor(SystemLoad load) {
    if (!load.available) return 'per-thread CPU not available on this system';
    final busiest = load.busiest;
    if (busiest == null) return 'measuring per-thread CPU…';
    return 'busiest thread: ${busiest.label} '
        '${SystemLoadPopover.formatThreadPercent(busiest.percent)} of a core'
        ' — click for every thread';
  }

  @override
  State<SystemLoadChip> createState() => _SystemLoadChipState();
}

class _SystemLoadChipState extends State<SystemLoadChip> {
  final _overlay = OverlayPortalController();
  final _link = LayerLink();

  @override
  void dispose() {
    if (_overlay.isShowing) _overlay.hide();
    super.dispose();
  }

  void _toggle() => _overlay.isShowing ? _overlay.hide() : _overlay.show();

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlay,
        overlayChildBuilder: _buildOverlay,
        child: ValueListenableBuilder<SystemLoad>(
          valueListenable: widget.load,
          builder: (context, load, _) => Tooltip(
            message: SystemLoadChip.tooltipFor(load),
            child: GestureDetector(
              key: SystemLoadChip.chipKey,
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PhiSpacing.s3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'SYS',
                        style: PhiType.caption().copyWith(color: PhiColors.fg3),
                      ),
                      const SizedBox(width: PhiSpacing.s2),
                      _Dot(level: load.level),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    return Stack(
      children: [
        // A transparent barrier: an outside click dismisses the popover.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _overlay.hide,
            child: const SizedBox.expand(),
          ),
        ),
        // The strip sits on the window's bottom edge, so the panel opens
        // upward, its right edge on the chip's.
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.bottomRight,
          offset: const Offset(0, -PhiSpacing.s1),
          child: Align(
            alignment: Alignment.bottomRight,
            child: Material(
              color: Colors.transparent,
              child: ValueListenableBuilder<SystemLoad>(
                valueListenable: widget.load,
                builder: (context, load, _) => SystemLoadPopover(load: load),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The 8px status dot, glowing once the busiest thread is past ok.
class _Dot extends StatelessWidget {
  const _Dot({required this.level});

  final SystemLoadLevel level;

  @override
  Widget build(BuildContext context) {
    final colour = SystemLoadColours.forLevel(level);
    final glow =
        level == SystemLoadLevel.busy || level == SystemLoadLevel.saturated;
    return Container(
      key: SystemLoadChip.dotKey,
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: colour,
        shape: BoxShape.circle,
        boxShadow: glow
            ? [BoxShadow(color: colour.withValues(alpha: 0.5), blurRadius: 8)]
            : null,
      ),
    );
  }
}
