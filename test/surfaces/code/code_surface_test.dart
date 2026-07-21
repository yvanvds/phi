import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/design/widgets/toggle/phi_toggle.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/code_evaluator.dart';
import 'package:phi/engine/bridge/no_op_code_evaluator.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/surfaces/code/code_editor_view.dart';
import 'package:phi/surfaces/code/code_error_strip.dart';
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

  // ── fresh toggle ─────────────────────────────────────────────────────────

  Future<void> evaluateFirstBlock(WidgetTester tester) async {
    final controller = editorController(tester);
    // Line 0 ("a = 1") is a one-line block.
    controller.selection = const CodeLineSelection(
      baseIndex: 0,
      baseOffset: 0,
      extentIndex: 0,
      extentOffset: 0,
    );
    await tester.pump();
    Actions.invoke(
      tester.element(find.byType(CodeEditor)),
      const EvaluateBlockIntent(),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('fresh off (default) submits the block source unchanged', (
    tester,
  ) async {
    await pumpSurface(tester);
    await evaluateFirstBlock(tester);

    expect(evaluator.calls.single, 'a = 1');
  });

  testWidgets('fresh on prefixes the block with yse.cancel_all()', (
    tester,
  ) async {
    await pumpSurface(tester);
    await tester.tap(find.byType(PhiToggle));
    await tester.pump();

    await evaluateFirstBlock(tester);

    expect(evaluator.calls.single, 'yse.cancel_all()\na = 1');
  });

  // ── traceback strip ──────────────────────────────────────────────────────

  testWidgets('a script-origin traceback renders in the strip with its line', (
    tester,
  ) async {
    await pumpSurface(tester);
    await evaluateFirstBlock(tester);

    evaluator.emit(
      const EvalStderr(
        'Traceback (most recent call last):\n'
        '  File "<script>", line 1, in <module>\n'
        "NameError: name 'a' is not defined",
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(CodeErrorStrip), findsOneWidget);
    expect(find.text('error · line 1'), findsOneWidget);
    expect(
      find.textContaining("NameError: name 'a' is not defined"),
      findsOneWidget,
    );
  });

  testWidgets('a callback-origin traceback still renders, verbatim', (
    tester,
  ) async {
    await pumpSurface(tester);
    // No evaluation — a scheduled callback raises with no <script> frame.
    evaluator.emit(
      const EvalStderr(
        'Traceback (most recent call last):\n'
        '  File "phi/__init__.py", line 90, in _tick\n'
        'RuntimeError: callback boom',
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(CodeErrorStrip), findsOneWidget);
    expect(find.text('error · callback'), findsOneWidget);
    expect(find.textContaining('RuntimeError: callback boom'), findsOneWidget);
  });

  testWidgets('the strip dismisses', (tester) async {
    await pumpSurface(tester);
    evaluator.emit(const EvalStderr('SyntaxError: bad'));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byType(CodeErrorStrip), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.byType(CodeErrorStrip), findsNothing);
  });

  // ── red / green flash ────────────────────────────────────────────────────

  int flashRgb(WidgetTester tester) {
    final box = tester.widget<ColoredBox>(
      find.byKey(CodeEditorView.flashOverlayKey),
    );
    return box.color.toARGB32() & 0x00FFFFFF;
  }

  testWidgets('a clean eval flashes the fuchsia (ok) tint', (tester) async {
    await pumpSurface(tester);
    await evaluateFirstBlock(tester);

    expect(flashRgb(tester), PhiColors.voice1Soft.toARGB32() & 0x00FFFFFF);
  });

  testWidgets('a matching traceback turns the flash red', (tester) async {
    await pumpSurface(tester);
    await evaluateFirstBlock(tester);
    expect(flashRgb(tester), PhiColors.voice1Soft.toARGB32() & 0x00FFFFFF);

    evaluator.emit(
      const EvalStderr('  File "<script>", line 1, in <module>\nBoom'),
    );
    await tester.pump(const Duration(milliseconds: 20));

    expect(flashRgb(tester), PhiColors.hot.toARGB32() & 0x00FFFFFF);
  });
}
