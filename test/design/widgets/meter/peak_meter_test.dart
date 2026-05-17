import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/meter/peak_meter.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('clamps negative input to zero fill', (tester) async {
    await tester.pumpWidget(host(const PeakMeter(level: -0.5)));
    await tester.pumpAndSettle();

    final fills = find.descendant(
      of: find.byType(PeakMeter),
      matching: find.byType(AnimatedContainer),
    );
    final container = tester.widget<AnimatedContainer>(fills);
    expect(container.constraints?.maxHeight ?? 0, 0);
  });

  testWidgets('clamps values above 1.0 to full fill', (tester) async {
    const meterHeight = 80.0;
    await tester.pumpWidget(
      host(const PeakMeter(level: 1.7, height: meterHeight)),
    );
    await tester.pumpAndSettle();

    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(PeakMeter),
        matching: find.byType(AnimatedContainer),
      ),
    );
    // height-2 from the 1px padding on each side.
    expect(container.constraints?.maxHeight ?? 0, meterHeight - 2);
  });

  testWidgets('mid-range level produces a partial fill', (tester) async {
    const meterHeight = 100.0;
    await tester.pumpWidget(
      host(const PeakMeter(level: 0.5, height: meterHeight)),
    );
    await tester.pumpAndSettle();

    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(PeakMeter),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(
      container.constraints?.maxHeight ?? 0,
      closeTo((meterHeight - 2) * 0.5, 0.01),
    );
  });
}
