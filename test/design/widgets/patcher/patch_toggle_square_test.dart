import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_voices.dart';
import 'package:phi/design/widgets/patcher/patch_toggle_square.dart';

/// The `.t` object is Max's square-with-a-mark (issue #381) — no `TOGGLE`
/// header over a pill, just a square that carries a cross when it is on.
void main() {
  Future<void> pump(WidgetTester tester, {required bool value}) =>
      tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox.fromSize(
              size: const Size.square(32),
              child: PatchToggleSquare(value: value, voice: 3),
            ),
          ),
        ),
      );

  testWidgets('off is a bare square — no mark, no caption', (tester) async {
    await pump(tester, value: false);

    expect(find.byType(Text), findsNothing);
    expect(find.byType(CustomPaint), findsNothing);
  });

  testWidgets('on draws the cross and goes voiced', (tester) async {
    await pump(tester, value: true);

    expect(find.byType(CustomPaint), findsOneWidget);
    final decoration =
        tester.widget<DecoratedBox>(find.byType(DecoratedBox)).decoration
            as BoxDecoration;
    expect((decoration.border! as Border).top.color, PhiVoices.color(3));
    expect(decoration.boxShadow, isNotNull);
  });

  testWidgets('fills its whole square', (tester) async {
    await pump(tester, value: true);
    expect(
      tester.getSize(find.byType(PatchToggleSquare)),
      const Size.square(32),
    );
  });
}
