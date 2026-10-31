import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_note_swatch.dart';
import '../../tokens/phi_radii.dart';
import 'patch_canvas_constants.dart';
import 'patch_note_metrics.dart';

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
/// text, spaces and line breaks included — laid out by
/// [PatchNoteMetrics.span]: it wraps at the note's width (issue #488), keeps
/// every `\n`, and sets a line led by `# ` as a heading. The box is sized by
/// [PatchNoteMetrics.sizeFor] from the very same span, so the wrap the
/// measurement predicted is the wrap that renders. An empty note shows a dim
/// [placeholder] instead of collapsing to an unclickable sliver.
///
/// A note can be given a **colour** (issue #511): a [swatch] replaces the
/// paper field, ink and frame with one of the [PhiNoteSwatch] token triples,
/// resolved against the ambient theme's brightness so the ink always pairs
/// with its field — headings included, since they take the same ink. With no
/// swatch the note looks exactly as it always did.
///
/// Visual-only and unaware of `PatchNode`/`PatcherController`; the canvas's
/// raw pointer pipeline owns every press over it — select, drag, and the
/// double-click that opens the inline box to edit the text.
class PatchNoteBox extends StatelessWidget {
  const PatchNoteBox({
    required this.text,
    this.textKey,
    this.swatch,
    super.key,
  });

  /// The note's content — the object's raw creation-argument string. Blank
  /// renders (and measures) as [placeholder].
  final String text;

  /// Key placed on the rendered text, so a test can name the text of one
  /// specific note on a canvas full of nodes.
  final Key? textKey;

  /// The note's colour, or null for the plain paper look.
  final PhiNoteSwatch? swatch;

  /// What an empty note reads — dim, so it invites the double-click that
  /// fills it in.
  static const String placeholder = 'note';

  /// The text a note with [text] renders — and therefore the text it must be
  /// **measured** from: the trimmed content (interior line breaks kept), or
  /// [placeholder] when there is none. One function so the sizing (`PatcherController`) and the render
  /// can never disagree about the box the text needs.
  static String displayText(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? placeholder : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final empty = text.trim().isEmpty;
    final s = swatch;
    final brightness = Theme.of(context).brightness;
    final field = s?.bg(brightness) ?? PhiColors.noteBg;
    final ink = s?.fg(brightness) ?? PhiColors.noteFg;
    final frame = s?.line(brightness) ?? PhiColors.noteLine;
    // The empty-note hint is dim either way: the plain paper's faint fg3, or
    // the swatch's own ink at half strength (fg3 would vanish on a light field).
    final hint = s == null ? PhiColors.fg3 : ink.withValues(alpha: 0.5);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: field,
        border: Border.all(
          color: frame,
          width: PatchCanvasConstants.nodeBorderWidth,
        ),
        borderRadius: PhiRadii.all3,
      ),
      child: Padding(
        // Padding *and* border, so the text area is exactly the one
        // [PatchNoteMetrics.sizeFor] wrapped the text in — a couple of pixels
        // more here would move a wrap and leave the box the wrong height.
        padding: const EdgeInsets.symmetric(
          horizontal: PatchNoteMetrics.paddingH,
          vertical: PatchNoteMetrics.paddingV,
        ),
        child: Align(
          alignment: Alignment.topLeft,
          // Clipped rather than overflowing: during the frame a resize is
          // re-measuring, the text must not paint past the paper.
          child: ClipRect(
            child: Text.rich(
              PatchNoteMetrics.span(
                displayText(text),
                color: empty ? hint : ink,
              ),
              key: textKey,
              softWrap: true,
              // The measurement has no notion of the platform text scale, so
              // neither may the render — or the two disagree about the wrap.
              textScaler: TextScaler.noScaling,
            ),
          ),
        ),
      ),
    );
  }
}
