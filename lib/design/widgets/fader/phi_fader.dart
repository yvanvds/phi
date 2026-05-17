import 'package:flutter/material.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_radii.dart';
import '../../tokens/phi_spacing.dart';
import '../../tokens/phi_type.dart';

/// Vertical fader control. Voice-coloured fill rises from the bottom of the
/// track; the thumb is a bordered cap that glows in the same voice colour.
///
/// [value] is in `[0.0, 1.0]`. Drag the thumb or tap anywhere on the track to
/// reposition; both gestures emit through [onChanged].
class PhiFader extends StatelessWidget {
  const PhiFader({
    required this.value,
    required this.onChanged,
    this.readout,
    this.label,
    this.height = 160,
    this.voiceColor = PhiColors.voice1,
    this.voiceGlow = PhiColors.voice1Soft,
    super.key,
  });

  /// Current value in `[0.0, 1.0]`.
  final double value;

  /// Emitted on tap and drag with the new value in `[0.0, 1.0]`.
  final ValueChanged<double> onChanged;

  /// Optional readout shown above the track (e.g. `"-12.4"`, `"0.62"`).
  final String? readout;

  /// Optional caption shown below the track (e.g. `"master"`).
  final String? label;

  /// Pixel height of the fader track.
  final double height;

  /// Voice colour used for the thumb border, fill, and readout glow.
  final Color voiceColor;

  /// Soft variant of [voiceColor] used for outer glows.
  final Color voiceGlow;

  static const double _trackWidth = 24;
  static const double _thumbHeight = 24;
  static const double _thumbOverhang = 5;

  double _toValue(double localY) {
    final clamped = localY.clamp(0.0, height);
    return 1.0 - (clamped / height);
  }

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    final fillFraction = clamped;
    final thumbCentreFromTop = (1.0 - clamped) * height;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (readout != null)
          Padding(
            padding: const EdgeInsets.only(bottom: PhiSpacing.s2),
            child: Text(
              readout!,
              style: PhiType.readout().copyWith(
                color: voiceColor,
                shadows: [Shadow(color: voiceGlow, blurRadius: 8)],
              ),
            ),
          ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => onChanged(_toValue(d.localPosition.dy)),
          onVerticalDragStart: (d) => onChanged(_toValue(d.localPosition.dy)),
          onVerticalDragUpdate: (d) => onChanged(_toValue(d.localPosition.dy)),
          child: SizedBox(
            width: _trackWidth + _thumbOverhang * 2,
            height: height,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: _trackWidth,
                  height: height,
                  decoration: BoxDecoration(
                    color: PhiColors.bg1,
                    border: Border.all(color: PhiColors.line1),
                    borderRadius: PhiRadii.all2,
                  ),
                ),
                Positioned(
                  left: (_trackWidth + _thumbOverhang * 2 - 1) / 2,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 1, color: PhiColors.line1),
                ),
                Positioned(
                  left: _thumbOverhang,
                  right: _thumbOverhang,
                  bottom: 0,
                  height: height * fillFraction,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: voiceColor,
                      boxShadow: [BoxShadow(color: voiceGlow, blurRadius: 10)],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: (thumbCentreFromTop - _thumbHeight / 2).clamp(
                    0.0,
                    height - _thumbHeight,
                  ),
                  height: _thumbHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: PhiColors.bg3,
                      border: Border.all(color: PhiColors.lineHot),
                      borderRadius: PhiRadii.all2,
                      boxShadow: [BoxShadow(color: voiceGlow, blurRadius: 12)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(top: PhiSpacing.s2),
            child: Text(label!, style: PhiType.caption()),
          ),
      ],
    );
  }
}
