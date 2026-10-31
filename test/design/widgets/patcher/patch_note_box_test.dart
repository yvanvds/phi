import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/design/tokens/phi_note_swatch.dart';
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
    PhiNoteSwatch? swatch,
    Brightness? brightness,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == null ? null : ThemeData(brightness: brightness),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: PatchNoteBox(text: text, swatch: swatch),
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

  group('colour (issue #511)', () {
    const heading = '# Try this\nturn the knob';
    final headingSize = PatchNoteMetrics.sizeFor(display: heading);

    for (final brightness in Brightness.values) {
      testWidgets('a swatch paints its ${brightness.name} field, frame and '
          'ink — heading included', (tester) async {
        const s = PhiNoteSwatch.cyan;
        await pump(
          tester,
          heading,
          size: headingSize,
          swatch: s,
          brightness: brightness,
        );
        final deco = decorationOf(tester);
        expect(deco.color, s.bg(brightness));
        expect(deco.border!.top.color, s.line(brightness));
        final root =
            tester.widget<Text>(find.text('Try this\nturn the knob')).textSpan!
                as TextSpan;
        expect(root.style!.color, s.fg(brightness));
        final head = root.children!.first as TextSpan;
        expect(head.style!.color, s.fg(brightness));
      });

      testWidgets(
        'no swatch is the plain paper look under ${brightness.name}',
        (tester) async {
          await pump(tester, 'a note', brightness: brightness);
          final deco = decorationOf(tester);
          expect(deco.color, PhiColors.noteBg);
          expect(deco.border!.top.color, PhiColors.noteLine);
          expect(inkOf(tester, 'a note'), PhiColors.noteFg);
        },
      );
    }

    test('the dark and light variants are distinct fields', () {
      for (final s in PhiNoteSwatch.all) {
        expect(s.bgDark, isNot(s.bgLight), reason: s.name);
        expect(s.bg(Brightness.dark), s.bgDark);
        expect(s.bg(Brightness.light), s.bgLight);
      }
    });

    testWidgets('an empty coloured note dims its own ink for the hint', (
      tester,
    ) async {
      const s = PhiNoteSwatch.amber;
      await pump(tester, '', swatch: s, brightness: Brightness.light);
      expect(
        inkOf(tester, PatchNoteBox.placeholder),
        s.fgLight.withValues(alpha: 0.5),
      );
    });

    test('every swatch keeps its ink readable on its field (WCAG AAA, 7:1) '
        'in both themes', () {
      double contrast(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        final hi = la > lb ? la : lb;
        final lo = la > lb ? lb : la;
        return (hi + 0.05) / (lo + 0.05);
      }

      for (final s in PhiNoteSwatch.all) {
        for (final b in Brightness.values) {
          expect(
            contrast(s.fg(b), s.bg(b)),
            greaterThanOrEqualTo(7),
            reason: '${s.name} (${b.name})',
          );
        }
        // Dark ink on a pale field in light; pale ink on a dim field in dark.
        expect(s.bgDark.computeLuminance(), lessThan(0.05), reason: s.name);
        expect(s.bgLight.computeLuminance(), greaterThan(0.6), reason: s.name);
      }
    });

    test('a note stores the token name; an unknown one is no swatch', () {
      for (final s in PhiNoteSwatch.all) {
        expect(s.name, startsWith('note-'));
        expect(PhiNoteSwatch.byName(s.name), same(s));
      }
      expect(
        {for (final s in PhiNoteSwatch.all) s.name}.length,
        PhiNoteSwatch.all.length,
      );
      expect(PhiNoteSwatch.byName(''), isNull);
      expect(PhiNoteSwatch.byName('#ff0000'), isNull);
      expect(PhiNoteSwatch.byName('note-plaid'), isNull);
    });
  });
}
