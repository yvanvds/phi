import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/code_evaluator.dart';
import 'package:phi/engine/bridge/real_code_evaluator.dart';

/// [RealCodeEvaluator] runs blocks through the engine's `LiveCoding.run` and
/// republishes `LiveCoding.errors` tracebacks onto its [events] stream. These
/// drive both seams with fakes (a recording `run` and a controllable `errors`
/// stream) — the "fake `LiveCoding` seam" the issue calls for — so the wiring is
/// proven without an embedded interpreter (issue #232).
void main() {
  late List<String> submitted;
  late StreamController<String> errors;

  setUp(() {
    submitted = [];
    errors = StreamController<String>.broadcast();
  });

  tearDown(() => errors.close());

  RealCodeEvaluator build() =>
      RealCodeEvaluator(run: submitted.add, errors: errors.stream);

  test(
    'evaluate forwards the source to LiveCoding.run and reports ok',
    () async {
      final evaluator = build();
      final outcome = await evaluator.evaluate('yse.send("cutoff", 0.4)');

      expect(submitted, ['yse.send("cutoff", 0.4)']);
      // Fire-and-forget: acceptance is the only synchronous signal.
      expect(outcome.ok, isTrue);
      await evaluator.dispose();
    },
  );

  test('an engine traceback surfaces as an EvalStderr event', () async {
    final evaluator = build();
    final frames = <EvalEvent>[];
    evaluator.events.listen(frames.add);

    errors.add('Traceback...\n  File "<script>", line 1\nNameError: nope');
    await pumpEventQueue();

    expect(frames, hasLength(1));
    expect(frames.single, isA<EvalStderr>());
    expect((frames.single as EvalStderr).text, contains('NameError: nope'));
    await evaluator.dispose();
  });

  test('dispose cancels the error subscription and closes events', () async {
    final evaluator = build();
    final frames = <EvalEvent>[];
    evaluator.events.listen(frames.add);

    await evaluator.dispose();
    // A traceback arriving after dispose must not throw or emit.
    errors.add('late traceback');
    await pumpEventQueue();

    expect(frames, isEmpty);
  });
}
