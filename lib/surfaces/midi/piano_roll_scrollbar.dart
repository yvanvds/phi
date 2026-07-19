import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';

/// A thin draggable scrollbar for one axis of the zoomed piano roll (issue
/// #198). It is deliberately unit-agnostic: [contentExtent], [viewportExtent]
/// and [offset] are all in the same abstract units — beats for the horizontal
/// bar, semitone lanes for the vertical one — so the same widget drives both
/// axes off the shared [PianoRollView].
///
/// It renders nothing while the whole content fits ([viewportExtent] ≥
/// [contentExtent]), so the fitted (un-zoomed) roll stays clean; once zoomed in
/// the thumb reflects `viewportExtent / contentExtent` of the track and reports
/// a fresh clamped [offset] through [onScrollTo] as it is dragged.
class PianoRollScrollbar extends StatelessWidget {
  const PianoRollScrollbar({
    required this.axis,
    required this.contentExtent,
    required this.viewportExtent,
    required this.offset,
    required this.onScrollTo,
    this.thickness = defaultThickness,
    super.key,
  });

  final Axis axis;

  /// Total scrollable content along [axis], in offset units (must be > 0).
  final double contentExtent;

  /// The slice of [contentExtent] the viewport currently shows.
  final double viewportExtent;

  /// Current scroll position — the offset of the content under the leading edge,
  /// in `[0, contentExtent - viewportExtent]`.
  final double offset;

  /// Requests a new (already clamped by the caller's view) scroll [offset].
  final ValueChanged<double> onScrollTo;

  /// Cross-axis size of the bar.
  final double thickness;

  /// Default bar thickness — also the inset the roll leaves at the crossing
  /// corner so the two bars don't overlap.
  static const double defaultThickness = 9;

  /// Smallest the thumb shrinks to, so it stays grabbable when zoomed way in.
  static const double _minThumb = 24;

  bool get _scrollable =>
      viewportExtent > 0 && contentExtent > viewportExtent + 1e-9;

  @override
  Widget build(BuildContext context) {
    if (!_scrollable) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackLength = axis == Axis.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        if (trackLength <= 0) return const SizedBox.shrink();

        final maxOffset = contentExtent - viewportExtent;
        final thumbLength = (trackLength * viewportExtent / contentExtent)
            .clamp(_minThumb, trackLength)
            .toDouble();
        final thumbTravel = trackLength - thumbLength;
        final t = maxOffset <= 0 ? 0.0 : (offset / maxOffset).clamp(0.0, 1.0);
        final thumbStart = thumbTravel * t;
        // Offset units gained per pixel the thumb is dragged.
        final gain = thumbTravel <= 0 ? 0.0 : maxOffset / thumbTravel;

        void drag(double deltaPixels) {
          if (gain == 0) return;
          onScrollTo((offset + deltaPixels * gain).clamp(0.0, maxOffset));
        }

        final horizontal = axis == Axis.horizontal;
        return Stack(
          children: [
            Positioned(
              left: horizontal ? thumbStart : 0,
              top: horizontal ? 0 : thumbStart,
              width: horizontal ? thumbLength : thickness,
              height: horizontal ? thickness : thumbLength,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => drag(horizontal ? d.delta.dx : d.delta.dy),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: PhiColors.fg3,
                      borderRadius: PhiRadii.allPill,
                      border: Border.all(color: PhiColors.line2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
