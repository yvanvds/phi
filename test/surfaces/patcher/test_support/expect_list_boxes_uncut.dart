import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phi/design/widgets/patcher/patch_list_box.dart';

/// Checks that **every** `.l` list box on screen shows its list in full, with
/// room to spare (issues #533, #538).
///
/// A list box draws its list on one line and ends a list longer than its width
/// with an ellipsis, so a tutorial whose box is too narrow for the result it
/// shows leaves the reader guessing. The tutorial integration tests call this
/// before they close a tutorial, so every list box result the walk-through
/// produced is checked — not only the ones the test reads back. [where] names
/// the tutorial in the failure message.
///
/// Each list is held to [expectListTextFits], not to "no ellipsis on this
/// machine": a pass here must predict a pass on every platform CI runs.
void expectListBoxesUncut(WidgetTester tester, {String where = ''}) {
  final texts = find.descendant(
    of: find.byType(PatchListBox),
    matching: find.byType(Text),
  );
  for (final e in texts.evaluate()) {
    expectListTextFits(e, where: where);
  }
}

/// Room one character of a list box's line takes, in ems of its font size:
/// JetBrains Mono's 0.6 em advance plus the 0.01 em tracking `PhiType.monoS`
/// adds.
const double _advanceEm = 0.61;

/// Checks that the list box text at [element] (a [Text] inside a
/// [PatchListBox]) fits its line **with one character to spare**, measured
/// both ways (issue #538):
///
/// - as laid out, in whatever font this platform resolved, and
/// - as the monospace estimate `characters × 0.61 em`, which does not depend
///   on the platform's text shaping at all.
///
/// The larger of the two, plus one spare character, must fit the width the
/// box gives its text. So a box that only just fits on one machine — where a
/// different rasteriser, a font fallback, or one more digit in a list whose
/// length depends on timing would tip it into an ellipsis — fails everywhere,
/// not only on the platform that renders it widest.
void expectListTextFits(Element element, {String where = ''}) {
  final text = (element.widget as Text).data ?? '';
  final paragraph = element.renderObject! as RenderParagraph;
  final fontSize = paragraph.text.style?.fontSize ?? 11;
  final char = _advanceEm * fontSize;
  final laidOut = paragraph.getMaxIntrinsicWidth(double.infinity);
  final needed = math.max(laidOut, text.length * char) + char;
  final room = paragraph.constraints.maxWidth;
  final at = where.isEmpty ? '' : ' of $where';
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '"$text" is cut off in a list box$at',
  );
  expect(
    needed,
    lessThanOrEqualTo(room),
    reason:
        '"$text" fits a list box$at with no character to spare: it needs '
        '${needed.toStringAsFixed(1)} px of a ${room.toStringAsFixed(1)} px '
        'line, so another platform or a longer run may cut it off',
  );
}
