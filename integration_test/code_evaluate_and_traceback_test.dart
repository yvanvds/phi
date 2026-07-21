import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/code_evaluator.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/code/code_editor_view.dart';
import 'package:phi/surfaces/code/code_error_strip.dart';
import 'package:re_editor/re_editor.dart';

import '../test/engine/test_doubles/fake_code_evaluator.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that the Code surface's evaluator path is real (issue #232),
/// through the actual workstation — real rail navigation, real fonts, real
/// layout. The embedded interpreter can't run in CI, so a `FakeCodeEvaluator`
/// stands in for `RealCodeEvaluator`: running a block dispatches source and the
/// fake emits an engine-style traceback, which must surface in the inline strip
/// (with its parsed `<script>` line) and turn the eval flash red.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  int flashRgb(WidgetTester tester) {
    final box = tester.widget<ColoredBox>(
      find.byKey(CodeEditorView.flashOverlayKey),
    );
    return box.color.toARGB32() & 0x00FFFFFF;
  }

  testWidgets(
    'code: running a block shows its traceback and reddens the flash',
    (tester) async {
      late final FakeCodeEvaluator evaluator;
      evaluator = FakeCodeEvaluator(
        // A run that raises: the engine delivers this traceback on its error
        // channel a moment later.
        onEvaluate: (_) => evaluator.emit(
          const EvalStderr(
            'Traceback (most recent call last):\n'
            '  File "<script>", line 1, in <module>\n'
            "NameError: name 'gain' is not defined",
          ),
        ),
      );
      final engine = PhiEngine(
        FakeYseGateway(),
        midiGateway: FakeMidiGateway(),
        telemetryInterval: const Duration(milliseconds: 20),
      );
      final session = SessionState();

      await tester.pumpWidget(
        PhiApp(engine: engine, session: session, codeEvaluator: evaluator),
      );
      await tester.pumpAndSettle();

      // Navigate to the Code surface and run the block under the cursor.
      await tester.tap(railFor(SurfaceId.code));
      await tester.pumpAndSettle();
      Actions.invoke(
        tester.element(find.byType(CodeEditor)),
        const EvaluateBlockIntent(),
      );
      // A short pump (not settle): keep the flash mid-decay so we can read it.
      await tester.pump(const Duration(milliseconds: 20));

      expect(evaluator.calls, isNotEmpty);
      // The traceback surfaced inline, with its parsed <script> line.
      expect(find.byType(CodeErrorStrip), findsOneWidget);
      expect(find.text('error · line 1'), findsOneWidget);
      expect(
        find.textContaining("NameError: name 'gain' is not defined"),
        findsOneWidget,
      );
      // And the eval flash went red.
      expect(flashRgb(tester), PhiColors.hot.toARGB32() & 0x00FFFFFF);

      session.dispose();
      await engine.dispose();
      await evaluator.dispose();
    },
  );
}
