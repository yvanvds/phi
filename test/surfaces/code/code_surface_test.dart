import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/no_op_code_evaluator.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/surfaces/code/code_editor_view.dart';
import 'package:phi/surfaces/code/code_projected_view.dart';
import 'package:phi/surfaces/code/code_surface.dart';
import 'package:re_editor/re_editor.dart';

import '../../engine/test_doubles/fake_code_evaluator.dart';
import '../../engine/test_doubles/fake_patcher_gateway.dart';
import '../../engine/test_doubles/fake_yse_gateway.dart';

const _seed = 'a = 1\n\ndef foo():\n    return 2\n\nfoo()\n';

void main() {
  late FakeYseGateway gateway;
  late FakePatcherGateway patcherGateway;
  late PhiEngine engine;
  late SessionState session;
  late FakeCodeEvaluator evaluator;

  setUp(() {
    gateway = FakeYseGateway();
    patcherGateway = FakePatcherGateway();
    engine = PhiEngine(
      gateway,
      patcherGateway: patcherGateway,
      telemetryInterval: const Duration(milliseconds: 50),
    );
    session = SessionState();
    evaluator = FakeCodeEvaluator();
  });

  tearDown(() async {
    await evaluator.dispose();
    session.dispose();
    await engine.dispose();
    await gateway.dispose();
  });

  Future<void> pumpSurface(WidgetTester tester, {String seed = _seed}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeSurface(
            engine: engine,
            session: session,
            evaluator: evaluator,
            seedSource: seed,
          ),
        ),
      ),
    );
    // re_editor schedules a `Future.delayed(10ms)` from its text-input
    // connection setup. Advance the clock past it so the binding's
    // pending-timer guard doesn't fail teardown.
    await tester.pump(const Duration(milliseconds: 20));
  }

  CodeLineEditingController editorController(WidgetTester tester) {
    final CodeEditor codeEditor = tester.widget(find.byType(CodeEditor));
    return codeEditor.controller!;
  }

  testWidgets('renders the editor view by default', (tester) async {
    await pumpSurface(tester);
    expect(find.byType(CodeEditor), findsOneWidget);
    expect(find.byType(CodeEditorView), findsOneWidget);
    expect(find.byType(CodeProjectedView), findsNothing);
  });

  testWidgets('EvaluateBlockIntent dispatch sends block source to evaluator', (
    tester,
  ) async {
    await pumpSurface(tester);
    final controller = editorController(tester);
    // Place the cursor on line 3 ("    return 2"), inside the
    // "def foo():\n    return 2" block.
    controller.selection = const CodeLineSelection(
      baseIndex: 3,
      baseOffset: 0,
      extentIndex: 3,
      extentOffset: 0,
    );
    await tester.pump();

    Actions.invoke(
      tester.element(find.byType(CodeEditor)),
      const EvaluateBlockIntent(),
    );
    await tester.pump(const Duration(milliseconds: 20));

    expect(evaluator.calls, hasLength(1));
    expect(evaluator.calls.single, 'def foo():\n    return 2');
  });

  testWidgets('toggling session.projection swaps to the projected view', (
    tester,
  ) async {
    await pumpSurface(tester);
    session.toggleProjection();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(CodeProjectedView), findsOneWidget);
    expect(find.byType(CodeEditor), findsNothing);
  });

  testWidgets('projected view strips full-line comments', (tester) async {
    await pumpSurface(tester, seed: '# header\na = 1\n# trailing');
    session.toggleProjection();
    await tester.pump(const Duration(milliseconds: 20));

    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    final hasStripped = richTexts.any((r) {
      final plain = r.text.toPlainText();
      return plain.contains('a = 1') &&
          !plain.contains('# header') &&
          !plain.contains('# trailing');
    });
    expect(hasStripped, isTrue);
  });

  testWidgets('NoOpCodeEvaluator default does not throw', (_) async {
    final noop = NoOpCodeEvaluator();
    final outcome = await noop.evaluate('x = 1');
    expect(outcome.ok, isTrue);
    await noop.dispose();
  });
}
