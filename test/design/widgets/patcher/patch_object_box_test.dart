import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/design/tokens/phi_voices.dart';
import 'package:phi/design/widgets/patcher/patch_canvas_constants.dart';
import 'package:phi/design/widgets/patcher/patch_object_box.dart';
import 'package:phi/design/widgets/patcher/patch_port_dot.dart';

/// The object box (issue #379, design §7): one bordered line of mono text with
/// no header at all, its ports straddling the top and bottom edges exactly as
/// the frame it replaces drew them (issue #377), and the armed voice border +
/// glow carried over unchanged.
///
/// Since issue #380 the line is also the one thing saying DSP or control, in
/// colour rather than in a `~`/`.` glyph.
void main() {
  const boxSize = Size(120, 26);

  Future<void> pumpBox(
    WidgetTester tester, {
    String text = 'sine 440',
    bool isDsp = true,
    bool armed = false,
    int voice = 1,
    List<double> inputXs = const [],
    List<double> outputXs = const [],
    Size size = boxSize,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox.fromSize(
            size: size,
            child: PatchObjectBox(
              text: text,
              isDsp: isDsp,
              voice: voice,
              armed: armed,
              inputPortXs: inputXs,
              outputPortXs: outputXs,
              inputVoices: [for (final _ in inputXs) voice],
              outputVoices: [for (final _ in outputXs) voice],
            ),
          ),
        ),
      ),
    );
  }

  /// The single decoration the box paints its border and fill with.
  BoxDecoration decoration(WidgetTester tester) =>
      tester
              .widget<DecoratedBox>(
                find.descendant(
                  of: find.byType(PatchObjectBox),
                  matching: find.byType(DecoratedBox),
                ),
              )
              .decoration
          as BoxDecoration;

  testWidgets('renders its line and nothing else — no header, no title', (
    tester,
  ) async {
    await pumpBox(tester);

    expect(find.text('sine 440'), findsOneWidget);
    // The whole node is one Text: a header would be a second one.
    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets('the domain is the line colour, not a drawn prefix', (
    tester,
  ) async {
    Color lineColor() => tester.widget<Text>(find.byType(Text)).style!.color!;

    await pumpBox(tester, text: 'sine 440');
    expect(lineColor(), PhiColors.cool);

    await pumpBox(tester, text: 'metro 250', isDsp: false);
    expect(lineColor(), PhiColors.fg1);

    // And nothing prints the glyph the colour replaced.
    expect(find.textContaining('~'), findsNothing);
    expect(find.text('.metro 250'), findsNothing);
  });

  testWidgets('the line is a single ellipsised one, never wrapped', (
    tester,
  ) async {
    await pumpBox(tester, text: 'metro 250 with a very long argument list');

    final line = tester.widget<Text>(find.byType(Text));
    expect(line.maxLines, 1);
    expect(line.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unarmed, the border is the neutral line colour', (tester) async {
    await pumpBox(tester);

    final d = decoration(tester);
    expect(d.color, PhiColors.bg1);
    expect(d.border!.top.color, PhiColors.line1);
    expect(d.border!.top.width, PatchCanvasConstants.nodeBorderWidth);
    expect(d.boxShadow, isNull);
  });

  testWidgets('armed, the border goes voiced and the box glows', (
    tester,
  ) async {
    await pumpBox(tester, armed: true, voice: 3);

    final d = decoration(tester);
    expect(d.border!.top.color, PhiVoices.color(3));
    expect(d.boxShadow!.single.color, PhiVoices.glow(3));
  });

  testWidgets('inlets straddle the top edge and outlets the bottom one', (
    tester,
  ) async {
    await pumpBox(tester, inputXs: const [16, 42], outputXs: const [16]);

    final box = tester.getRect(find.byType(PatchObjectBox));
    expect(find.byType(PatchPortDot), findsNWidgets(3));

    final centres = [
      for (var i = 0; i < 3; i++)
        tester.getCenter(find.byType(PatchPortDot).at(i)),
    ];
    expect(centres[0], Offset(box.left + 16, box.top));
    expect(centres[1], Offset(box.left + 42, box.top));
    // A cable leaves this box's bottom edge and arrives at the next one's top.
    expect(centres[2], Offset(box.left + 16, box.bottom));
  });

  testWidgets('a portless box draws no dots at all', (tester) async {
    await pumpBox(tester);
    expect(find.byType(PatchPortDot), findsNothing);
  });
}
