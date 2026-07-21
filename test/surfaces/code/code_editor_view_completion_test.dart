import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/surfaces/code/code_editor_view.dart';
import 'package:phi/surfaces/code/code_eval_flash.dart';
import 'package:phi/surfaces/code/completion/phi_completion_list_view.dart';
import 'package:phi/surfaces/code/completion/phi_completion_prompts_builder.dart';
import 'package:re_editor/re_editor.dart';

import '../../engine/test_doubles/fake_code_evaluator.dart';

void main() {
  late FakeCodeEvaluator evaluator;
  late CodeEvalFlash flash;
  late ValueNotifier<bool> fresh;
  late CodeLineEditingController controller;

  setUp(() {
    evaluator = FakeCodeEvaluator();
    flash = CodeEvalFlash();
    fresh = ValueNotifier<bool>(false);
    controller = CodeLineEditingController.fromText('voice.\n');
  });

  tearDown(() async {
    controller.dispose();
    fresh.dispose();
    flash.dispose();
    await evaluator.dispose();
  });

  Future<void> pump(WidgetTester tester, {ProjectRegistry? registry}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: CodeEditorView(
              controller: controller,
              evaluator: evaluator,
              flash: flash,
              fresh: fresh,
              registry: registry,
            ),
          ),
        ),
      ),
    );
    // re_editor's input connection schedules a 10ms timer on mount.
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('hosts the completion popup when a registry is supplied', (
    tester,
  ) async {
    final registry = ProjectRegistry();
    addTearDown(registry.dispose);
    await pump(tester, registry: registry);

    final autocomplete = tester.widget<CodeAutocomplete>(
      find.byType(CodeAutocomplete),
    );
    expect(autocomplete.promptsBuilder, isA<PhiCompletionPromptsBuilder>());

    // The overlay it would show is our Phi-flavoured list view.
    final view = autocomplete.viewBuilder(
      tester.element(find.byType(CodeEditor)),
      ValueNotifier(
        const CodeAutocompleteEditingValue(input: '', prompts: [], index: 0),
      ),
      (_) {},
    );
    expect(view, isA<PhiCompletionListView>());
  });

  testWidgets('hosts no completion without a registry', (tester) async {
    await pump(tester);
    expect(find.byType(CodeAutocomplete), findsNothing);
    expect(find.byType(CodeEditor), findsOneWidget);
  });
}
