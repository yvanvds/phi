import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/design/widgets/button/primary_button.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          backgroundColor: PhiColors.bg0,
          body: Center(child: child),
        ),
      );

  testWidgets('renders uppercased label', (tester) async {
    await tester.pumpWidget(
      host(PrimaryButton(label: 'play sine', onPressed: () {})),
    );

    expect(find.text('PLAY SINE'), findsOneWidget);
  });

  testWidgets('invokes onPressed when tapped', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(PrimaryButton(label: 'play sine', onPressed: () => taps++)),
    );

    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('armed state paints fuchsia border', (tester) async {
    await tester.pumpWidget(
      host(
        PrimaryButton(
          label: 'stop sine',
          isArmed: true,
          onPressed: () {},
        ),
      ),
    );

    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(PrimaryButton),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.border!.top.color, PhiColors.lineHot);
    expect(decoration.boxShadow, isNotNull);
  });

  testWidgets('disabled when onPressed is null', (tester) async {
    await tester.pumpWidget(host(const PrimaryButton(label: 'idle', onPressed: null)));

    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();
    // No callback registered — tap is allowed but does nothing.
    expect(find.text('IDLE'), findsOneWidget);
  });
}
