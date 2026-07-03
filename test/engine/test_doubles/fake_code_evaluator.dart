import 'dart:async';

import 'package:phi/engine/bridge/code_evaluator.dart';

/// Records every [evaluate] call so widget tests can assert on what the
/// editor surface sent. The default outcome is `EvalOutcome.ok()`; set
/// [nextOutcome] to return something different on the next call.
///
/// [onEvaluate] stands in for the side-effects a real Python kernel would have
/// when a block runs — most importantly registering a custom transform into a
/// `CustomTransformRegistry` (issue #38). Tests set it to simulate the
/// live-coding → registration handshake without an embedded interpreter.
class FakeCodeEvaluator implements CodeEvaluator {
  FakeCodeEvaluator({this.onEvaluate});

  final List<String> calls = [];
  EvalOutcome? nextOutcome;

  /// Invoked with the source on each [evaluate], before the outcome is
  /// returned. Lets a test register transforms, emit events, etc.
  final void Function(String source)? onEvaluate;

  final StreamController<EvalEvent> _events = StreamController.broadcast();
  bool _disposed = false;

  @override
  Future<EvalOutcome> evaluate(String source) async {
    calls.add(source);
    onEvaluate?.call(source);
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
