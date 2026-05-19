import 'dart:async';

import 'package:phi/engine/bridge/code_evaluator.dart';

/// Records every [evaluate] call so widget tests can assert on what the
/// editor surface sent. The default outcome is `EvalOutcome.ok()`; set
/// [nextOutcome] to return something different on the next call.
class FakeCodeEvaluator implements CodeEvaluator {
  FakeCodeEvaluator();

  final List<String> calls = [];
  EvalOutcome? nextOutcome;
  final StreamController<EvalEvent> _events = StreamController.broadcast();
  bool _disposed = false;

  @override
  Future<EvalOutcome> evaluate(String source) async {
    calls.add(source);
    final outcome = nextOutcome ?? const EvalOutcome.ok();
    nextOutcome = null;
    return outcome;
  }

  void emit(EvalEvent event) => _events.add(event);

  @override
  Stream<EvalEvent> get events => _events.stream;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _events.close();
  }
}
