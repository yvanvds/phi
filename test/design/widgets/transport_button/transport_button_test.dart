import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/design/widgets/transport_button/transport_button.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('invokes onPressed when tapped', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        TransportButton(
          icon: Icons.play_arrow,
          tooltip: 'play',
          onPressed: () => taps++,
        ),
      ),
    );

    await tester.tap(find.byType(TransportButton));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('active state paints fuchsia border and tints icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        TransportButton(
          icon: Icons.play_arrow,
          tooltip: 'play',
          isActive: true,
          onPressed: () {},
        ),
      ),
    );

    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(TransportButton),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.border!.top.color, PhiColors.lineHot);

    final icon = tester.widget<Icon>(find.byIcon(Icons.play_arrow));
    expect(icon.color, PhiColors.voice1);
  });
}
