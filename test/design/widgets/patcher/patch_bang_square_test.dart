import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_voices.dart';
import 'package:phi/design/widgets/patcher/patch_bang_square.dart';

/// The `.b` object is a square with a ring in it, and nothing else (issue
/// #381) — no `BUTTON` header, no `bang` caption inside it.
void main() {
  Future<void> pump(WidgetTester tester, {required bool flash}) =>
      tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox.fromSize(
              size: const Size.square(32),
              child: PatchBangSquare(flash: flash, voice: 2),
            ),
          ),
        ),
      );

  testWidgets('carries no caption of any kind', (tester) async {
    await pump(tester, flash: false);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('fills its whole square', (tester) async {
    await pump(tester, flash: false);
    expect(tester.getSize(find.byType(PatchBangSquare)), const Size.square(32));
  });

  testWidgets('lights up in its voice colour while the bang is firing', (
    tester,
  ) async {
    await pump(tester, flash: false);
    final idle =
        tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration
            as BoxDecoration;
    expect(idle.boxShadow, isNull);

    await pump(tester, flash: true);
    final firing =
        tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration
            as BoxDecoration;
    // The only feedback a momentary trigger can give: a brief voiced glow.
    expect(firing.boxShadow, isNotNull);
    expect((firing.border! as Border).top.color, PhiVoices.color(2));
  });
}
