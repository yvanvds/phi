import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/checklist/phi_checklist_row.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 240, child: child)),
    ),
  );

  testWidgets('renders the label', (tester) async {
    await tester.pumpWidget(
      host(
        PhiChecklistRow(
          label: 'Keystation 61',
          value: false,
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Keystation 61'), findsOneWidget);
  });

  testWidgets('unchecked shows no check mark', (tester) async {
    await tester.pumpWidget(
      host(PhiChecklistRow(label: 'port', value: false, onChanged: (_) {})),
    );

    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('checked shows the check mark', (tester) async {
    await tester.pumpWidget(
      host(PhiChecklistRow(label: 'port', value: true, onChanged: (_) {})),
    );

    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('tapping the row toggles the value', (tester) async {
    bool? received;
    await tester.pumpWidget(
      host(
        PhiChecklistRow(
          label: 'port',
          value: false,
          onChanged: (v) => received = v,
        ),
      ),
    );

    await tester.tap(find.byType(PhiChecklistRow));
    await tester.pump();

    expect(received, isTrue);
  });

  testWidgets('tapping a checked row toggles it off', (tester) async {
    bool? received;
    await tester.pumpWidget(
      host(
        PhiChecklistRow(
          label: 'port',
          value: true,
          onChanged: (v) => received = v,
        ),
      ),
    );

    await tester.tap(find.byType(PhiChecklistRow));
    await tester.pump();

    expect(received, isFalse);
  });

  testWidgets('renders the trailing slot', (tester) async {
    await tester.pumpWidget(
      host(
        PhiChecklistRow(
          label: 'port',
          value: true,
          onChanged: (_) {},
          trailing: const Icon(Icons.circle, key: ValueKey('activity-dot')),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('activity-dot')), findsOneWidget);
  });

  testWidgets('a null onChanged disables the tap target', (tester) async {
    await tester.pumpWidget(
      host(const PhiChecklistRow(label: 'port', value: false, onChanged: null)),
    );

    final gesture = tester.widget<GestureDetector>(
      find.descendant(
        of: find.byType(PhiChecklistRow),
        matching: find.byType(GestureDetector),
      ),
    );
    expect(gesture.onTap, isNull);
  });
}
