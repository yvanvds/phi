import 'dart:async';

import 'package:yse/yse.dart';

import 'code_evaluator.dart';

/// The live [CodeEvaluator] — runs Code-surface blocks through the engine's
/// embedded CPython (`LiveCoding.run`) and forwards uncaught Python errors
/// (`LiveCoding.errors`) onto the [events] stream as [EvalStderr] frames
/// (design `docs/design/live-coding.md` §5, issue #232).
///
/// `LiveCoding.run` is **fire-and-forget**: the engine takes a copy of the
/// script and evaluates it on its own script thread, so there is no synchronous
/// success/failure to report — [evaluate] returns [EvalOutcome.ok] the moment
/// the chunk is accepted. A block that raises surfaces *asynchronously* over
/// [LiveCoding.errors] (delivered on the main isolate during `System.update()`),
/// which this evaluator republishes on [events]; the Code surface's traceback
/// strip and red flash read it from there. This is the one error sink the yse
/// spec guarantees — no silent failures.
///
/// The `LiveCoding` façade is a set of stateless C globals, so [run] and
/// [errors] are injectable for tests: a fake `run` records submissions and a
/// fake `errors` controller drives tracebacks, exercising the whole surface
/// without an embedded interpreter (the "fake `LiveCoding` seam" the issue
/// calls for). Production leaves them null and binds `LiveCoding.run` /
/// `LiveCoding.errors`.
class RealCodeEvaluator implements CodeEvaluator {
  RealCodeEvaluator({void Function(String source)? run, Stream<String>? errors})
    : _run = run ?? LiveCoding.run {
    // Subscribing here (rather than lazily on the first [events] listener)
    // installs the engine error callback up front, so a traceback from a
    // scheduled callback is captured even before the strip attaches.
    _errorSub = (errors ?? LiveCoding.errors).listen((traceback) {
      if (!_events.isClosed) _events.add(EvalStderr(traceback));
    });
  }

  final void Function(String source) _run;
  late final StreamSubscription<String> _errorSub;
  final StreamController<EvalEvent> _events =
      StreamController<EvalEvent>.broadcast();

  @override
  Future<EvalOutcome> evaluate(String source) async {
    _run(source);
    // Fire-and-forget: acceptance is the only synchronous signal; a raising
    // block reports later over [events].
    return const EvalOutcome.ok();
  }

  @override
  Stream<EvalEvent> get events => _events.stream;

  @override
  Future<void> dispose() async {
    await _errorSub.cancel();
    await _events.close();
  }
}
