import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/design/widgets/patcher/patch_note_box.dart';
import 'package:phi/design/widgets/patcher/patch_note_metrics.dart';
import 'package:phi/design/widgets/patcher/patch_object_box_metrics.dart';

/// The sticky note the annotation object renders as (issue #436): free text
/// on its own warm paper field, framed softly — nothing about it says
/// "device". Colours are the `note-*` tokens from
/// `design system/colors_and_type.css`. Since issue #488 the text wraps at the
/// note's width, keeps its line breaks and sets a `# ` line as a heading — and
/// the box [PatchNoteMetrics] measures is the box the text actually needs.
void main() {
  const paragraph =
      'A sine runs into the dac. Drag the slider to sweep its frequency '
      'and listen to how the pitch follows; then try a saw instead.';

  Future<void> pump(
    WidgetTester tester,
    String text, {
    Size size = const Size(160, 24),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
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

  RenderParagraph paragraphOf(WidgetTester tester) =>
      tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byType(PatchNoteBox),
          matching: find.byType(RichText),
        ),
      );

  /// The ink colour of the whole text — set on the root span.
  Color? inkOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).textSpan!.style!.color;

  testWidgets('renders the whole content, spaces included', (tester) async {
    await pump(tester, 'warm pad from here');
    expect(find.text('warm pad from here'), findsOneWidget);
  });

  testWidgets('paper field and ink are the note tokens', (tester) async {
    await pump(tester, 'a note');
    final deco = decorationOf(tester);
    expect(deco.color, PhiColors.noteBg);
    expect(deco.border!.top.color, PhiColors.noteLine);
    expect(inkOf(tester, 'a note'), PhiColors.noteFg);
  });

  testWidgets('an empty note shows a dim placeholder, not a sliver', (
    tester,
  ) async {
    await pump(tester, '   ');
    expect(find.text(PatchNoteBox.placeholder), findsOneWidget);
    expect(inkOf(tester, PatchNoteBox.placeholder), PhiColors.fg3);
  });

  test('displayText is the measured text: content, or the placeholder', () {
    expect(PatchNoteBox.displayText(' warm pad '), 'warm pad');
    expect(PatchNoteBox.displayText(' one\ntwo\n'), 'one\ntwo');
    expect(PatchNoteBox.displayText(''), PatchNoteBox.placeholder);
    expect(PatchNoteBox.displayText('  '), PatchNoteBox.placeholder);
  });

  group('wrapping and line breaks (issue #488)', () {
    testWidgets('a paragraph wraps at the note width, inside the box', (
      tester,
    ) async {
      final size = PatchNoteMetrics.sizeFor(display: paragraph);
      await pump(tester, paragraph, size: size);

      final text = paragraphOf(tester);
      final lineHeight =
          PatchObjectBoxMetrics.sizeFor(
            text: 'x',
            inputs: 0,
            outputs: 0,
          ).height -
          2 * PatchNoteMetrics.paddingV;
      expect(text.size.height, greaterThan(lineHeight * 2));
      // The measured box is exactly what the render needs: the text fits
      // the inner area, with no line clipped off the bottom.
      expect(
        text.size.height,
        lessThanOrEqualTo(size.height - 2 * PatchNoteMetrics.paddingV),
      );
      expect(text.didExceedMaxLines, isFalse);
    });

    testWidgets('an explicit break is a new line', (tester) async {
      final one = PatchNoteMetrics.sizeFor(display: 'first');
      final two = PatchNoteMetrics.sizeFor(display: 'first\nsecond');
      expect(two.height, greaterThan(one.height));

      await pump(tester, 'first\nsecond', size: two);
      expect(find.text('first\nsecond'), findsOneWidget);
    });

    testWidgets('a `# ` line is a heading, marker dropped', (tester) async {
      const text = '# Tutorial\nbody text';
      await pump(tester, text, size: PatchNoteMetrics.sizeFor(display: text));

      final root =
          tester.widget<Text>(find.text('Tutorial\nbody text')).textSpan!
              as TextSpan;
      final heading = root.children!.first as TextSpan;
      final body = root.children!.last as TextSpan;
      expect(heading.toPlainText(), 'Tutorial\n');
      expect(heading.style!.fontSize, greaterThan(root.style!.fontSize!));
      expect(body.style, isNull, reason: 'body runs in the root style');
      expect(heading.style!.color, PhiColors.noteFg);
    });
  });

  group('PatchNoteMetrics.sizeFor', () {
    test(
      'a short note shrink-wraps, a long one stops at the default width',
      () {
        final short = PatchNoteMetrics.sizeFor(display: 'warm pad');
        expect(short.width, lessThan(PatchNoteMetrics.defaultWidth));
        expect(
          short,
          PatchObjectBoxMetrics.sizeFor(
            text: 'warm pad',
            inputs: 0,
            outputs: 0,
          ),
          reason: 'a one-line note is the box it was before it could wrap',
        );
        expect(
          PatchNoteMetrics.sizeFor(display: paragraph).width,
          PatchNoteMetrics.defaultWidth,
        );
      },
    );

    test('a resized note is its width, and narrower is taller', () {
      final wide = PatchNoteMetrics.sizeFor(display: paragraph, width: 400);
      final narrow = PatchNoteMetrics.sizeFor(display: paragraph, width: 120);
      expect(wide.width, 400);
      expect(narrow.width, 120);
      expect(narrow.height, greaterThan(wide.height));
    });

    test('the width is held to the resize range', () {
      expect(
        PatchNoteMetrics.sizeFor(display: 'a', width: 1).width,
        PatchNoteMetrics.minWidth,
      );
      expect(
        PatchNoteMetrics.sizeFor(display: 'a', width: 1e6).width,
        PatchNoteMetrics.maxWidth,
      );
    });
  });
}
