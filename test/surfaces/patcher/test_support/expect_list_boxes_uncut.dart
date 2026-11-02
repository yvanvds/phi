import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_list_box.dart';

/// Checks that **every** `.l` list box on screen shows its list in full
/// (issue #533).
///
/// A list box draws its list on one line and ends a list longer than its width
/// with an ellipsis, so a tutorial whose box is too narrow for the result it
/// shows leaves the reader guessing. The tutorial integration tests call this
/// before they close a tutorial, so every list box result the walk-through
/// produced is checked — not only the ones the test reads back. [where] names
/// the tutorial in the failure message.
void expectListBoxesUncut(WidgetTester tester, {String where = ''}) {
  final texts = find.descendant(
    of: find.byType(PatchListBox),
    matching: find.byType(Text),
  );
  for (final e in texts.evaluate()) {
    final text = (e.widget as Text).data;
    expect(
      (e.renderObject! as RenderParagraph).didExceedMaxLines,
      isFalse,
      reason: '"$text" is cut off in a list box of $where',
    );
  }
}
