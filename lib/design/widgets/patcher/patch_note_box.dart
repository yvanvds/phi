import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_radii.dart';
import 'patch_canvas_constants.dart';
import 'patch_object_box_metrics.dart';

/// A **note** on the canvas: the annotation object (`.text`) rendered as a
/// sticky note rather than a patch object (issue #436).
///
/// The counterpart of [PatchObjectBox] for content that *is not part of the
/// instrument*: a note has no ports, no name to print, no domain colour — it
/// is the performer's comment sitting on the patch, so everything about the
/// box says "paper, not device". The frame is softer (a warm hairline on the
/// widest radius the system has, instead of the object box's crisp border),
/// the field is the warm `noteBg` paper tone rather than the panel dark, and
/// the ink is `noteFg` rather than the mono foreground — all three from
/// `design system/colors_and_type.css`. No port dots are drawn, because a
/// note has nothing to connect.
///
/// The text is the object's creation-argument string shown **whole** — free
/// text, spaces included — in the very [PatchObjectBoxMetrics.lineStyle] the
/// box was measured with, so the note and the object boxes share one
/// baseline. An empty note shows a dim [placeholder] instead of collapsing
/// to an unclickable sliver.
///
/// Visual-only and unaware of `PatchNode`/`PatcherController`; the canvas's
/// raw pointer pipeline owns every press over it — select, drag, and the
/// double-click that opens the inline box to edit the text.
class PatchNoteBox extends StatelessWidget {
  const PatchNoteBox({required this.text, this.textKey, super.key});

  /// The note's content — the object's raw creation-argument string. Blank
  /// renders (and measures) as [placeholder].
  final String text;

  /// Key placed on the rendered line, so a test can name the text of one
  /// specific note on a canvas full of nodes.
  final Key? textKey;

  /// What an empty note reads — dim, so it invites the double-click that
  /// fills it in.
  static const String placeholder = 'note';

  /// The line a note with [text] renders — and therefore the line it must be
  /// **measured** from: the trimmed content, or [placeholder] when there is
  /// none. One function so the sizing (`PatcherController`) and the render
  /// can never disagree about the box the text needs.
  static String displayText(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? placeholder : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = text.trim();
    final empty = trimmed.isEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PhiColors.noteBg,
        border: Border.all(
          color: PhiColors.noteLine,
          width: PatchCanvasConstants.nodeBorderWidth,
        ),
        borderRadius: PhiRadii.all3,
      ),
      child: Padding(
        // The object box's own padding, because the note is measured with the
        // object box's metrics — see [PatchObjectBoxMetrics.sizeFor].
        padding: const EdgeInsets.symmetric(
          horizontal: PatchCanvasConstants.objectBoxPaddingH,
          vertical: PatchCanvasConstants.objectBoxPaddingV,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            displayText(text),
            key: textKey,
            style: PatchObjectBoxMetrics.lineStyle().copyWith(
              color: empty ? PhiColors.fg3 : PhiColors.noteFg,
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
