import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/inline_editable_text/inline_editable_text.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('shows value as text initially', (tester) async {
    await tester.pumpWidget(
      host(InlineEditableText(value: 'untitled', onChanged: (_) {})),
    );

    expect(find.text('untitled'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('tapping reveals a TextField pre-seeded with the value', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(InlineEditableText(value: 'untitled', onChanged: (_) {})),
    );

    await tester.tap(find.text('untitled'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'untitled');
  });

  testWidgets('submitting commits the new value via onChanged', (tester) async {
    String? committed;
    await tester.pumpWidget(
      host(
        InlineEditableText(value: 'untitled', onChanged: (v) => committed = v),
      ),
    );

    await tester.tap(find.text('untitled'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'drone study');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(committed, 'drone study');
    expect(find.byType(TextField), findsNothing);
  });
}
