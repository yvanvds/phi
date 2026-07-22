import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/runtime/runtime_variable.dart';
import 'package:phi/domain/state_machine/store/state_trigger.dart';
import 'package:phi/surfaces/state/state_trigger_editor.dart';

/// The trigger editor dialog (issue #244): kind + params, seeded from the
/// stored trigger, returning the edited [StateTrigger] on save.
void main() {
  final drum = EntityAddress.parse('domain.drum');
  final pad = EntityAddress.parse('domain.pad');

  StateTrigger? result;
  var closed = false;

  Future<void> open(
    WidgetTester tester, {
    StateTrigger initial = const ManualTrigger(),
    List<TriggerDomainOption>? domains,
    List<RuntimeVariable> variables = const [],
  }) async {
    result = null;
    closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await StateTriggerEditor.show(
                context,
                initial: initial,
                domains:
                    domains ??
                    [
                      (address: drum, tempo: 124.0),
                      (address: pad, tempo: 90.0),
                    ],
                variables: variables,
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> pickKind(WidgetTester tester, String kind) async {
    await tester.tap(find.byKey(StateTriggerEditor.kindKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(kind).last);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(StateTriggerEditor.saveKey));
    await tester.pumpAndSettle();
  }

  testWidgets('manual in, cancel out — no trigger returned', (tester) async {
    await open(tester);
    expect(find.text('trigger'), findsOneWidget);
    await tester.tap(find.byKey(StateTriggerEditor.cancelKey));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets('switching to timed reveals beats + domain and saves a '
      'TimedTrigger', (tester) async {
    await open(tester);
    expect(find.byKey(StateTriggerEditor.beatsKey), findsNothing);

    await pickKind(tester, 'timed');
    expect(find.byKey(StateTriggerEditor.beatsKey), findsOneWidget);
    expect(find.byKey(StateTriggerEditor.domainKey), findsOneWidget);

    await tester.enterText(find.byKey(StateTriggerEditor.beatsKey), '16');
    await tester.tap(find.byKey(StateTriggerEditor.domainKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pad · 90 bpm'));
    await tester.pumpAndSettle();

    await save(tester);
    expect(result, TimedTrigger(beats: 16, domain: pad));
  });

  testWidgets('a stored timed trigger seeds its fields', (tester) async {
    await open(tester, initial: TimedTrigger(beats: 8.5, domain: pad));
    expect(find.text('timed'), findsOneWidget);
    expect(find.text('8.5'), findsOneWidget);
    expect(find.text('pad · 90 bpm'), findsOneWidget);
    await save(tester);
    expect(result, TimedTrigger(beats: 8.5, domain: pad));
  });

  testWidgets('unparsable beats disable save', (tester) async {
    await open(tester);
    await pickKind(tester, 'timed');
    await tester.enterText(find.byKey(StateTriggerEditor.beatsKey), '0');
    await tester.pump();

    final button = tester.widget<TextButton>(
      find.byKey(StateTriggerEditor.saveKey),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('variable kind picks a defined variable and one of its values', (
    tester,
  ) async {
    await open(
      tester,
      variables: [
        RuntimeVariable(name: 'section', values: const ['a', 'b']),
        RuntimeVariable(name: 'mode', values: const ['x', 'y']),
      ],
    );
    await pickKind(tester, 'variable');

    // Defaults to the first definition and its first candidate.
    await tester.tap(find.byKey(StateTriggerEditor.nameKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('mode').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(StateTriggerEditor.valueKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('y').last);
    await tester.pumpAndSettle();

    await save(tester);
    expect(result, const VariableTrigger(name: 'mode', value: 'y'));
  });

  testWidgets('a stored variable trigger naming an undefined variable stays '
      'offered', (tester) async {
    await open(
      tester,
      initial: const VariableTrigger(name: 'gone', value: 'x'),
      variables: [
        RuntimeVariable(name: 'section', values: const ['a', 'b']),
      ],
    );
    // The stored name and value render as the current selection.
    expect(find.text('gone'), findsOneWidget);
    expect(find.text('x'), findsOneWidget);
    await save(tester);
    expect(result, const VariableTrigger(name: 'gone', value: 'x'));
  });

  testWidgets('variable kind with nothing defined disables save', (
    tester,
  ) async {
    await open(tester);
    await pickKind(tester, 'variable');
    final button = tester.widget<TextButton>(
      find.byKey(StateTriggerEditor.saveKey),
    );
    expect(button.onPressed, isNull);
  });
}
