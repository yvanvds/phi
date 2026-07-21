import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/code_evaluator_factory.dart';
import 'package:phi/engine/bridge/no_op_code_evaluator.dart';

/// The factory gates the real evaluator behind `LiveCoding.enabled` so a
/// Python-less engine build still gets a working (no-op) Code surface. The
/// disabled branch is FFI-free and asserted here; the enabled branch constructs
/// a `RealCodeEvaluator`, which touches the native error callback, so it is
/// covered by the on-device run rather than headlessly (issue #232).
void main() {
  test('returns a NoOpCodeEvaluator when Python is disabled', () async {
    final evaluator = buildCodeEvaluator(pythonEnabled: false);
    expect(evaluator, isA<NoOpCodeEvaluator>());
    // A no-op accepts every chunk without a runtime.
    final outcome = await evaluator.evaluate('x = 1');
    expect(outcome.ok, isTrue);
    await evaluator.dispose();
  });
}
