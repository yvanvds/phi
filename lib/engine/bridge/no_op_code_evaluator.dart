import 'dart:async';

import 'code_evaluator.dart';

/// The default [CodeEvaluator] — accepts every chunk, emits nothing,
/// has no runtime. Lets the Code surface ship and remain useful while
/// the real kernel decision stays open.
class NoOpCodeEvaluator implements CodeEvaluator {
  NoOpCodeEvaluator();

  final StreamController<EvalEvent> _events = StreamController.broadcast();

  @override
  Future<EvalOutcome> evaluate(String source) async => const EvalOutcome.ok();

  @override
  Stream<EvalEvent> get events => _events.stream;

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}
