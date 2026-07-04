import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/runtime/runtime_variable_registry.dart';
import 'package:phi/surfaces/midi/graph/runtime_variables_bar.dart';

void main() {
  late RuntimeVariableRegistry registry;

  setUp(() => registry = RuntimeVariableRegistry());
  tearDown(() => registry.dispose());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RuntimeVariablesBar(registry: registry)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows a hint when no variables are defined', (tester) async {
    await pump(tester);
    expect(find.textContaining('no runtime variables'), findsOneWidget);
  });

  testWidgets('renders a variable name and its value segments', (tester) async {
    registry.define(name: 'mode', values: ['lead', 'pad']);
    await pump(tester);
    expect(find.textContaining('mode'), findsOneWidget);
    expect(find.text('LEAD'), findsOneWidget);
    expect(find.text('PAD'), findsOneWidget);
  });

  testWidgets('tapping a value segment sets the variable live', (tester) async {
    registry.define(name: 'mode', values: ['lead', 'pad']);
    await pump(tester);
    expect(registry.byName('mode')!.current, 'lead');

    await tester.tap(find.text('PAD'));
    await tester.pump();

    expect(registry.byName('mode')!.current, 'pad');
  });

  testWidgets('the + var action defines a new variable', (tester) async {
    await pump(tester);

    await tester.tap(find.text('+ var'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'name (e.g. intensity)'),
      'intensity',
    );
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'values, comma-separated (e.g. low, high)',
      ),
      'low, high',
    );
    await tester.tap(find.text('define'));
    await tester.pumpAndSettle();

    expect(registry.contains('intensity'), isTrue);
    expect(registry.byName('intensity')!.values, ['low', 'high']);
    expect(find.text('LOW'), findsOneWidget);
    expect(find.text('HIGH'), findsOneWidget);
  });

  testWidgets('the × affordance removes a variable', (tester) async {
    registry.define(name: 'mode', values: ['lead']);
    await pump(tester);

    await tester.tap(find.text('×'));
    await tester.pump();

    expect(registry.contains('mode'), isFalse);
    expect(find.textContaining('no runtime variables'), findsOneWidget);
  });
}
