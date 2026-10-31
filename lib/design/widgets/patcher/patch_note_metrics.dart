import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../tokens/phi_type.dart';
import 'patch_canvas_constants.dart';
import 'patch_object_box_metrics.dart';

/// How a **note** (`.text`, issue #488) lays out its text, and how big its box
/// has to be for it.
///
/// The note's counterpart of [PatchObjectBoxMetrics], and measured for the same
/// reason: a node's box is model state the canvas positions and hit-tests from,
/// so it is computed here rather than discovered during a layout pass. One
/// [span] builds the text both the measurement and `PatchNoteBox` use, so the
/// two can never disagree about where a line wraps.
///
/// A note is not a one-liner. Its text **wraps** at the note's width and the
/// height follows, explicit line breaks (`\n`, typed as Shift+Enter) are kept,
/// and a line that starts with `# ` renders as a **heading** — the marker
/// dropped, the line set in the larger mono — which is enough for a tutorial
/// patch to carry a title without a second object type.
///
/// The width is either the one the note was **resized** to (the `w` GUI
/// property, saved with the patch) or, for a note nobody resized, its text's
/// own width capped at [defaultWidth]: a two-word label stays a small tag,
/// while a paragraph wraps at a readable measure instead of running across
/// the canvas.
abstract final class PatchNoteMetrics {
  /// The reading width a note that was never resized wraps at.
  static const double defaultWidth = 240;

  /// The narrowest a resize can make a note — a few characters, so it never
  /// becomes a sliver that cannot be grabbed again.
  static const double minWidth = 48;

  /// The widest a resize can make a note.
  static const double maxWidth = 1200;

  /// The marker that turns a line into a heading.
  static const String headingMarker = '# ';

  /// Horizontal padding inside the frame — the object box's padding plus the
  /// border, so the text area the box renders is exactly the one measured.
  static const double paddingH =
      PatchCanvasConstants.objectBoxPaddingH +
      PatchCanvasConstants.nodeBorderWidth;

  /// Vertical counterpart of [paddingH].
  static const double paddingV =
      PatchCanvasConstants.objectBoxPaddingV +
      PatchCanvasConstants.nodeBorderWidth;

  /// The style a heading line is painted in — the design system's large mono.
  /// Guarded like [PatchObjectBoxMetrics.lineStyle], for the same
  /// fire-and-forget font load.
  static TextStyle headingStyle() {
    late TextStyle style;
    runZonedGuarded(() => style = PhiType.monoL(), (_, _) {});
    return style;
  }

  /// [width] held to the resize range, rounded to a whole pixel.
  static double clampWidth(double width) =>
      width.clamp(minWidth, maxWidth).roundToDouble();

  /// The text a note with [display] content renders — and is measured from.
  ///
  /// The body runs in [PatchObjectBoxMetrics.lineStyle] (so a note shares the
  /// object boxes' baseline); each line led by [headingMarker] becomes a
  /// heading in [headingStyle] with the marker dropped. [color] tints every
  /// run — it never changes a metric, so the measurement passes none.
  static TextSpan span(String display, {Color? color}) {
    final body = PatchObjectBoxMetrics.lineStyle().copyWith(color: color);
    final heading = headingStyle().copyWith(color: color);
    final lines = display.split('\n');
    return TextSpan(
      style: body,
      children: [
        for (var i = 0; i < lines.length; i++)
          lines[i].startsWith(headingMarker)
              ? TextSpan(
                  text:
                      lines[i].substring(headingMarker.length) +
                      (i < lines.length - 1 ? '\n' : ''),
                  style: heading,
                )
              : TextSpan(text: lines[i] + (i < lines.length - 1 ? '\n' : '')),
      ],
    );
  }

  /// The box a note showing [display] needs — at [width] when it was resized,
  /// else shrink-wrapped to its text up to [defaultWidth].
  static Size sizeFor({required String display, double? width}) {
    final painter = TextPainter(
      text: span(display),
      textDirection: TextDirection.ltr,
    );
    final double outer;
    if (width != null) {
      outer = clampWidth(width);
    } else {
      // Intrinsic: the longest line, unwrapped. Rounded up for the same
      // reason the object box rounds — a fractional width rounded down is a
      // line that wraps for one missing pixel.
      painter.layout();
      outer = math.max(
        minWidth,
        math.min(
          painter.maxIntrinsicWidth.ceilToDouble() + 2 * paddingH,
          defaultWidth,
        ),
      );
    }
    painter.layout(maxWidth: outer - 2 * paddingH);
    final height = painter.height.ceilToDouble() + 2 * paddingV;
    painter.dispose();
    return Size(outer, height);
  }
}
