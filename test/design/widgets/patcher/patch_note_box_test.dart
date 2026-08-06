import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/design/widgets/patcher/patch_note_box.dart';

/// The sticky note the annotation object renders as (issue #436): free text
/// on its own warm paper field, framed softly — nothing about it says
/// "device". Colours are the `note-*` tokens from
/// `design system/colors_and_type.css`.
void main() {
  Future<void> pump(WidgetTester tester, String text) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 24,
              child: PatchNoteBox(text: text),
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration decorationOf(WidgetTester tester) =>
      tester
              .widget<DecoratedBox>(
                find.descendant(
                  of: find.byType(PatchNoteBox),
                  matching: find.byType(DecoratedBox),
                ),
              )
              .decoration
          as BoxDecoration;

  testWidgets('renders the whole content, spaces included', (tester) async {
    await pump(tester, 'warm pad from here');
    expect(find.text('warm pad from here'), findsOneWidget);
  });

  testWidgets('paper field and ink are the note tokens', (tester) async {
    await pump(tester, 'a note');
    final deco = decorationOf(tester);
    expect(deco.color, PhiColors.noteBg);
    expect(deco.border!.top.color, PhiColors.noteLine);
    expect(
      tester.widget<Text>(find.text('a note')).style!.color,
      PhiColors.noteFg,
    );
  });

  testWidgets('an empty note shows a dim placeholder, not a sliver', (
    tester,
  ) async {
    await pump(tester, '   ');
    expect(find.text(PatchNoteBox.placeholder), findsOneWidget);
    expect(
      tester.widget<Text>(find.text(PatchNoteBox.placeholder)).style!.color,
      PhiColors.fg3,
    );
  });

  test('displayText is the measured line: content, or the placeholder', () {
    expect(PatchNoteBox.displayText(' warm pad '), 'warm pad');
    expect(PatchNoteBox.displayText(''), PatchNoteBox.placeholder);
    expect(PatchNoteBox.displayText('  '), PatchNoteBox.placeholder);
  });
}
