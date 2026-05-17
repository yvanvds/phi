import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/design/widgets/capsule/capsule.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('renders label uppercased', (tester) async {
    await tester.pumpWidget(host(const Capsule(label: 'drum 124')));

    expect(find.text('DRUM 124'), findsOneWidget);
  });

  testWidgets('paints the colored border', (tester) async {
    await tester.pumpWidget(
      host(const Capsule(label: 'cool', color: PhiColors.voice2)),
    );

    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(Capsule),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration! as BoxDecoration;
    final borderTop = decoration.border!.top.color;
    expect(borderTop.r, closeTo(PhiColors.voice2.r, 0.001));
    expect(borderTop.g, closeTo(PhiColors.voice2.g, 0.001));
    expect(borderTop.b, closeTo(PhiColors.voice2.b, 0.001));
  });

  testWidgets('omits the dot when showDot is false', (tester) async {
    await tester.pumpWidget(
      host(const Capsule(label: 'dotless', showDot: false)),
    );

    expect(find.text('DOTLESS'), findsOneWidget);
    // With the dot removed, the inner Row has exactly one visible child: the
    // Text. The Row itself is still present.
    final row = tester.widget<Row>(
      find.descendant(of: find.byType(Capsule), matching: find.byType(Row)),
    );
    expect(row.children.length, 1);
  });
}
