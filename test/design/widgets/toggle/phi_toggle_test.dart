import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/design/widgets/toggle/phi_toggle.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('emits the opposite value on tap', (tester) async {
    bool? received;
    await tester.pumpWidget(
      host(PhiToggle(value: false, onChanged: (v) => received = v)),
    );

    await tester.tap(find.byType(PhiToggle));
    await tester.pumpAndSettle();

    expect(received, isTrue);
  });

  testWidgets('on state paints the lineHot border', (tester) async {
    await tester.pumpWidget(host(PhiToggle(value: true, onChanged: (_) {})));

    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(PhiToggle),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.border!.top.color, PhiColors.lineHot);
    expect(decoration.boxShadow, isNotNull);
  });
}
