import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/code/completion/phi_completion_resolver.dart';
import 'package:phi/domain/code/completion/phi_method_table.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/surfaces/code/completion/phi_completion_prompt.dart';
import 'package:phi/surfaces/code/completion/phi_completion_prompts_builder.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  late ProjectRegistry registry;
  late PhiCompletionPromptsBuilder builder;
  late BuildContext ctx;

  setUp(() {
    registry = ProjectRegistry();
    registry.createEntity(
      EntityAddress.parse('voice.bells'),
      payload: const {'color': 'voice3'},
    );
    registry.createEntity(
      EntityAddress.parse('voice.pad'),
      payload: const {'color': 'voice5'},
    );
    registry.createEntity(EntityAddress.parse('clip.drums.intro'));
    registry.createEntity(EntityAddress.parse('clip.drums.fill'));
    builder = PhiCompletionPromptsBuilder(PhiCompletionResolver(registry));
  });

  tearDown(() => registry.dispose());

  Future<void> pumpContext(WidgetTester tester) async {
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox();
        },
      ),
    );
  }

  CodeAutocompleteEditingValue? build(String line) => builder.build(
    ctx,
    CodeLine(line),
    CodeLineSelection.collapsed(index: 0, offset: line.length),
  );

  List<String> words(CodeAutocompleteEditingValue v) =>
      v.prompts.whereType<PhiCompletionPrompt>().map((p) => p.word).toList();

  testWidgets('a namespace dot yields registry-driven prompts', (tester) async {
    await pumpContext(tester);
    final value = build('voice.')!;
    expect(words(value), ['bells', 'pad']);
    expect(value.input, '');
    expect(value.index, 0);
  });

  testWidgets('a group dot narrows to the group members', (tester) async {
    await pumpContext(tester);
    expect(words(build('clip.drums.')!), ['intro', 'fill']);
  });

  testWidgets('a leaf dot yields the static method table', (tester) async {
    await pumpContext(tester);
    expect(words(build('voice.bells.')!), phiMethodTable);
  });

  testWidgets('a partial identifier is carried as the input', (tester) async {
    await pumpContext(tester);
    final value = build('voice.pa')!;
    expect(value.input, 'pa');
    expect(words(value), ['pad']);
  });

  testWidgets('a plain Python context yields no prompts (null)', (
    tester,
  ) async {
    await pumpContext(tester);
    expect(build('print('), isNull);
    expect(build('gain'), isNull);
    expect(build('foo.'), isNull);
  });
}
