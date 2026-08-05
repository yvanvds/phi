import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../tokens/phi_type.dart';
import 'patch_canvas_constants.dart';

/// How big an object box has to be to hold its line of text (design §7,
/// issue #379).
///
/// Measured rather than laid out, because a node's box is **model** state: the
/// canvas positions each node from `PatchNode.size` and the cable layer reads
/// port centres off the same rectangle, so a box that only discovered its width
/// during a Flutter layout pass would leave every cable a frame behind. The
/// controller therefore asks for the size at the two moments the line can
/// change — creation and a params edit — and stores it on the node.
///
/// Intrinsic in both axes: the width is what the text needs, floored by the
/// minimum width the port count demands (issue #377) and capped by
/// [PatchCanvasConstants.objectBoxMaxWidth], past which
/// [PatchObjectBox] ellipsises the line. The height is one text line plus the
/// padding — never a port count, which is exactly what moving the ports onto
/// the horizontal edges bought.
abstract final class PatchObjectBoxMetrics {
  /// The style an object box's line is painted in — the very one
  /// [PatchObjectBox] hands to its `Text`, so the measurement and the render
  /// can never disagree about the font.
  ///
  /// Wrapped because [PhiType] resolves its families through `google_fonts`,
  /// which kicks off a **fire-and-forget** load: a family that is not resident
  /// yet — no network, no binding, a plain `test()` with no widget tree —
  /// completes that future with an error nobody is awaiting, which lands on
  /// whatever zone happens to be running and fails an unrelated test. Swallowing
  /// it here is not hiding a problem: a font that failed to load is a font
  /// nothing is going to *render* with either, so the fallback metrics the
  /// returned style measures with are exactly the metrics the box will be drawn
  /// at. The style itself comes back regardless — the throw is in the load, not
  /// in the lookup.
  static TextStyle lineStyle() {
    late TextStyle style;
    runZonedGuarded(
      () => style = PhiType.monoS(),
      (_, _) {}, // the family stays unresolved; its fallback is what renders
    );
    return style;
  }

  /// The box [text] needs on a node with [inputs] inlets and [outputs]
  /// outlets.
  static Size sizeFor({
    required String text,
    required int inputs,
    required int outputs,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: lineStyle()),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    // Rounded up rather than taken raw: a fractional width that the box then
    // rounds down is a line that ellipsises for one missing pixel.
    final line = painter.width.ceilToDouble();
    final lineHeight = painter.height.ceilToDouble();
    painter.dispose();

    const horizontalChrome =
        2 *
        (PatchCanvasConstants.objectBoxPaddingH +
            PatchCanvasConstants.nodeBorderWidth);
    const verticalChrome =
        2 *
        (PatchCanvasConstants.objectBoxPaddingV +
            PatchCanvasConstants.nodeBorderWidth);

    // The port floor wins outright — including over the cap, since a box
    // narrower than its own ports would hang dots off its edges. The text is
    // what gives way, by ellipsising.
    final portFloor = PatchCanvasConstants.minWidthForPorts(
      math.max(inputs, outputs),
    );
    final wanted = math.min(
      line + horizontalChrome,
      PatchCanvasConstants.objectBoxMaxWidth,
    );
    return Size(math.max(portFloor, wanted), lineHeight + verticalChrome);
  }
}
