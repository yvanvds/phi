import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/design/tokens/phi_voices.dart';
import 'package:phi/domain/code/completion/phi_completion_item.dart';
import 'package:phi/domain/code/completion/phi_completion_item_kind.dart';
import 'package:phi/surfaces/code/completion/phi_completion_list_view.dart';
import 'package:phi/surfaces/code/completion/phi_completion_prompt.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  CodeAutocompleteEditingValue value({
    String input = '',
    int index = 0,
    List<PhiCompletionItem>? items,
  }) {
    final rows =
        items ??
        const [
          PhiCompletionItem(
            identifier: 'bells',
            kind: PhiCompletionItemKind.entity,
            namespace: 'voice',
            colorToken: 'voice3',
          ),
          PhiCompletionItem(
            identifier: 'drums',
            kind: PhiCompletionItemKind.group,
            namespace: 'clip',
          ),
          PhiCompletionItem(
            identifier: 'phrase_a',
            kind: PhiCompletionItemKind.entity,
            namespace: 'clip',
            bars: 4,
          ),
          PhiCompletionItem(
            identifier: 'note',
            kind: PhiCompletionItemKind.method,
          ),
        ];
    return CodeAutocompleteEditingValue(
      input: input,
      prompts: rows.map(PhiCompletionPrompt.new).toList(),
      index: index,
    );
  }

  Future<ValueNotifier<CodeAutocompleteEditingValue>> pumpView(
    WidgetTester tester, {
    CodeAutocompleteEditingValue? initial,
    ValueChanged<CodeAutocompleteResult>? onSelected,
  }) async {
    final notifier = ValueNotifier(initial ?? value());
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PhiCompletionListView(
              notifier: notifier,
              onSelected: onSelected ?? (_) {},
            ),
          ),
        ),
      ),
    );
    return notifier;
  }

  testWidgets('paints a colour swatch for a voice row', (tester) async {
    await pumpView(tester);
    final swatch = tester.widget<Container>(
      find.byKey(PhiCompletionListView.swatchKey('bells')),
    );
    final decoration = swatch.decoration! as BoxDecoration;
    expect(decoration.color, PhiVoices.colorForToken('voice3'));
  });

  testWidgets('paints a chevron for a group row', (tester) async {
    await pumpView(tester);
    expect(
      find.byKey(PhiCompletionListView.chevronKey('drums')),
      findsOneWidget,
    );
  });

  testWidgets('paints a bar-length badge for a clip row', (tester) async {
    await pumpView(tester);
    expect(find.text('4 bars'), findsOneWidget);
  });

  testWidgets('marks a method row with a call glyph', (tester) async {
    await pumpView(tester);
    expect(find.text('ƒ'), findsOneWidget);
    expect(find.text('()'), findsOneWidget);
  });

  testWidgets('highlights the selected row and follows index changes', (
    tester,
  ) async {
    final notifier = await pumpView(tester);

    Color? rowColor(String id) => tester
        .widget<Container>(find.byKey(PhiCompletionListView.rowKey(id)))
        .color;

    expect(rowColor('bells'), PhiColors.bg2);
    expect(rowColor('drums'), isNull);

    // Arrow-down moves re_editor's index; the view must follow it.
    notifier.value = notifier.value.copyWith(index: 1);
    await tester.pump();

    expect(rowColor('bells'), isNull);
    expect(rowColor('drums'), PhiColors.bg2);
  });

  testWidgets('tapping a row inserts only that identifier', (tester) async {
    CodeAutocompleteResult? selected;
    await pumpView(tester, onSelected: (r) => selected = r);

    await tester.tap(find.byKey(PhiCompletionListView.rowKey('phrase_a')));
    await tester.pump();

    expect(selected, isNotNull);
    expect(selected!.word, 'phrase_a');
  });

  testWidgets('highlights the typed prefix on a narrowed row', (tester) async {
    await pumpView(
      tester,
      initial: value(
        input: 'be',
        items: const [
          PhiCompletionItem(
            identifier: 'bells',
            kind: PhiCompletionItemKind.entity,
            namespace: 'voice',
            colorToken: 'voice3',
          ),
        ],
      ),
    );

    final labels = tester
        .widgetList<RichText>(find.byType(RichText))
        .where((r) => r.text.toPlainText() == 'bells');
    expect(labels, isNotEmpty);
  });
}
