import 'package:flutter/material.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_radii.dart';
import '../../tokens/phi_spacing.dart';
import '../../tokens/phi_type.dart';

/// Single mixer channel strip — voice-swatch dot, name, fader with an
/// overlaid peak meter, mute/solo buttons, and a numeric readout.
///
/// Stateless. The strip is a presentation: callers feed it the current
/// volume / peak / mute / solo and receive callbacks to mutate them.
/// `isMaster` flips the strip to its accent treatment (voice-coloured
/// border with a soft halo) and hides the mute/solo buttons — the master
/// has nothing to mute against.
class ChannelStrip extends StatelessWidget {
  const ChannelStrip({
    required this.name,
    required this.volume,
    required this.peak,
    required this.muted,
    required this.soloed,
    required this.voiceColor,
    required this.voiceGlow,
    required this.onVolumeChanged,
    this.onMuteToggle,
    this.onSoloToggle,
    this.isMaster = false,
    super.key,
  });

  /// Channel name shown in the header row.
  final String name;

  /// User-set volume in `[0.0, 1.0]`.
  final double volume;

  /// Most recent post-volume peak in `[0.0, 1.0+]`.
  final double peak;

  final bool muted;
  final bool soloed;

  /// Saturated swatch for the voice dot, fader fill and master glow.
  final Color voiceColor;

  /// Soft halo variant used for the master strip's outer glow.
  final Color voiceGlow;

  /// Whether this is the master strip — gets the accent border and hides
  /// the mute/solo buttons.
  final bool isMaster;

  final ValueChanged<double> onVolumeChanged;
  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;

  static const double width = 86;
  static const double _faderHeight = 160;
  static const double _faderTrackWidth = 14;
  static const double _faderThumbOverhang = 4;
  static const double _faderThumbHeight = 12;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(PhiSpacing.s2),
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        border: Border.all(color: isMaster ? voiceGlow : PhiColors.line1),
        borderRadius: PhiRadii.all1,
        boxShadow: isMaster
            ? [BoxShadow(color: voiceGlow, blurRadius: 16)]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: PhiSpacing.s2),
          _faderWithMeter(),
          const SizedBox(height: PhiSpacing.s2),
          _readout(),
          if (!isMaster) ...[
            const SizedBox(height: PhiSpacing.s2),
            _muteSoloButtons(),
          ],
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: voiceColor,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: voiceGlow, blurRadius: 4)],
          ),
        ),
        const SizedBox(width: PhiSpacing.s1),
        Expanded(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: PhiType.monoS().copyWith(
              color: muted ? PhiColors.fg3 : PhiColors.fg0,
            ),
          ),
        ),
      ],
    );
  }

  /// Key on the fader's hit-area — exposed so widget tests can locate the
  /// fader without depending on layout offsets.
  static const Key faderHitAreaKey = Key('ChannelStrip.faderHitArea');

  Widget _faderWithMeter() {
    final clampedVolume = volume.clamp(0.0, 1.0);
    final clampedPeak = peak.clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => onVolumeChanged(_yToValue(d.localPosition.dy)),
      onVerticalDragStart: (d) =>
          onVolumeChanged(_yToValue(d.localPosition.dy)),
      onVerticalDragUpdate: (d) =>
          onVolumeChanged(_yToValue(d.localPosition.dy)),
      child: SizedBox(
        key: faderHitAreaKey,
        height: _faderHeight,
        child: Center(
          child: SizedBox(
            width: _faderTrackWidth + _faderThumbOverhang * 2,
            height: _faderHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _trackBackground(),
                _peakFill(clampedPeak),
                _thumb(clampedVolume),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _trackBackground() {
    return Container(
      width: _faderTrackWidth,
      decoration: BoxDecoration(
        color: PhiColors.bg0,
        border: Border.all(color: PhiColors.line1),
        borderRadius: PhiRadii.all1,
      ),
    );
  }

  Widget _peakFill(double peak) {
    if (muted || peak <= 0) return const SizedBox.shrink();
    final fillHeight = (_faderHeight - 2) * peak;
    final greenEnd = (0.60 / peak).clamp(0.0, 1.0);
    final amberEnd = (0.85 / peak).clamp(0.0, 1.0);
    return Positioned(
      left: _faderThumbOverhang + 1,
      right: _faderThumbOverhang + 1,
      bottom: 1,
      height: fillHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: const [
              PhiColors.voice4,
              PhiColors.voice4,
              PhiColors.voice3,
              PhiColors.voice3,
              PhiColors.hot,
              PhiColors.hot,
            ],
            stops: [0, greenEnd, greenEnd, amberEnd, amberEnd, 1],
          ),
          boxShadow: [BoxShadow(color: _glow(peak), blurRadius: 6)],
        ),
      ),
    );
  }

  Widget _thumb(double volume) {
    final thumbBottom = _faderHeight * volume - _faderThumbHeight / 2;
    return Positioned(
      left: 0,
      right: 0,
      bottom: thumbBottom.clamp(0.0, _faderHeight - _faderThumbHeight),
      height: _faderThumbHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: PhiColors.bg3,
          border: Border.all(
            color: isMaster ? PhiColors.lineHot : PhiColors.line2,
          ),
          borderRadius: PhiRadii.all1,
          boxShadow: isMaster
              ? [BoxShadow(color: voiceGlow, blurRadius: 8)]
              : null,
        ),
      ),
    );
  }

  Widget _readout() {
    if (muted) {
      return Text(
        'muted',
        textAlign: TextAlign.center,
        style: PhiType.monoS().copyWith(color: PhiColors.fg3),
      );
    }
    final db = peak <= 0
        ? '−∞'
        : '−${(20 - peak.clamp(0.0, 1.0) * 20).toStringAsFixed(1)}';
    final color = peak > 0.85
        ? PhiColors.hot
        : peak > 0.60
        ? PhiColors.voice3
        : PhiColors.voice4;
    return Text(
      db,
      textAlign: TextAlign.center,
      style: PhiType.monoS().copyWith(
        color: color,
        shadows: peak > 0.05
            ? [Shadow(color: _glow(peak), blurRadius: 6)]
            : null,
      ),
    );
  }

  Widget _muteSoloButtons() {
    return Row(
      children: [
        Expanded(
          child: _StripButton(
            label: 'M',
            active: muted,
            activeColor: PhiColors.hot,
            onPressed: onMuteToggle,
          ),
        ),
        const SizedBox(width: PhiSpacing.s0),
        Expanded(
          child: _StripButton(
            label: 'S',
            active: soloed,
            activeColor: PhiColors.voice3,
            onPressed: onSoloToggle,
          ),
        ),
      ],
    );
  }

  double _yToValue(double localY) {
    final clamped = localY.clamp(0.0, _faderHeight);
    return 1.0 - (clamped / _faderHeight);
  }

  Color _glow(double peak) {
    if (peak > 0.85) return PhiColors.hot.withValues(alpha: 0.5);
    if (peak > 0.60) return PhiColors.voice3.withValues(alpha: 0.45);
    return PhiColors.voice4.withValues(alpha: 0.35);
  }
}

class _StripButton extends StatelessWidget {
  const _StripButton({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onPressed,
  });

  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? PhiColors.bg3 : PhiColors.bg0,
            border: Border.all(color: active ? activeColor : PhiColors.line1),
            borderRadius: PhiRadii.all1,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: PhiType.monoS().copyWith(
              color: active ? activeColor : PhiColors.fg2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
