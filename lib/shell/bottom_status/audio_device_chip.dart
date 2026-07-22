import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../diagnostics/audio_device_health.dart';

/// The status-bar audio-device health chip (design `docs/design/diagnostics.md`
/// §5): a compact, glanceable indicator of whether audio output is [ok],
/// [AudioDeviceHealth.reconnecting], or [AudioDeviceHealth.lost].
///
/// It watches [health] (derived by `AudioHealthMonitor` from `activeAudioState()`
/// plus device-change notices) and stays calm and muted while ok, tinting amber
/// while reconnecting and red once lost. Clicking it opens the settings dialog's
/// AUDIO section ([onTap]) so a device problem is one tap from the fix.
class AudioDeviceChip extends StatelessWidget {
  /// Watches [health]; [onTap] opens settings AUDIO (`null` disables the click,
  /// e.g. in the bare shell with no settings owner wired).
  const AudioDeviceChip({required this.health, this.onTap, super.key});

  /// The live health signal — the chip rebuilds on every change.
  final ValueListenable<AudioDeviceHealth> health;

  /// Opens the settings dialog's AUDIO section. `null` leaves the chip inert.
  final VoidCallback? onTap;

  /// Keys tests target the chip by.
  static const Key chipKey = Key('BottomStatus.audioChip');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioDeviceHealth>(
      valueListenable: health,
      builder: (context, state, _) {
        final look = _lookFor(state);
        return Tooltip(
          message: look.tooltip,
          child: GestureDetector(
            key: chipKey,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: MouseRegion(
              cursor: onTap == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.click,
              child: Container(
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s2),
                decoration: BoxDecoration(
                  color: look.fill,
                  borderRadius: PhiRadii.allPill,
                  border: Border.all(color: look.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(look.icon, size: 12, color: look.accent),
                    const SizedBox(width: 3),
                    Text(
                      look.label,
                      style: PhiType.caption().copyWith(color: look.accent),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The label shown for [state] — also the token the widget test asserts on.
  @visibleForTesting
  static String labelFor(AudioDeviceHealth state) => _lookFor(state).label;

  static _ChipLook _lookFor(AudioDeviceHealth state) {
    switch (state) {
      case AudioDeviceHealth.ok:
        return const _ChipLook(
          label: 'AUDIO',
          tooltip: 'audio device — open settings',
          icon: Icons.volume_up,
          accent: PhiColors.fg2,
          fill: PhiColors.bg2,
          border: PhiColors.line1,
        );
      case AudioDeviceHealth.reconnecting:
        return _ChipLook(
          label: 'RECONNECTING',
          tooltip:
              'audio device dropped — reconnecting; click to open settings',
          icon: Icons.sync,
          accent: PhiColors.warm,
          fill: PhiColors.warm.withValues(alpha: 0.14),
          border: PhiColors.warm,
        );
      case AudioDeviceHealth.lost:
        return _ChipLook(
          label: 'NO AUDIO',
          tooltip: 'no audio device — click to open settings',
          icon: Icons.volume_off,
          accent: PhiColors.hot,
          fill: PhiColors.hot.withValues(alpha: 0.14),
          border: PhiColors.hot,
        );
    }
  }
}

/// The per-state visual bundle the chip renders.
class _ChipLook {
  const _ChipLook({
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.accent,
    required this.fill,
    required this.border,
  });

  final String label;
  final String tooltip;
  final IconData icon;
  final Color accent;
  final Color fill;
  final Color border;
}
