import 'dart:async';

import '../../domain/log/log_recorder.dart';
import '../../engine/bridge/code_evaluator.dart';
import 'engine_log_level.dart';

/// Wires the two *log-only* sources into a [LogRecorder] (design
/// `docs/design/diagnostics.md` §2): the audio engine's stream and the Python
/// interpreter's tracebacks. The app's own surfaced notices do not come through
/// here — they go through the notice channel (`NoticeCenter`), which both toasts
/// and logs; these two sources only record.
///
/// Both streams are injected (the engine's `Log.messages` and the Code
/// evaluator's event stream), so the whole coordinator is exercised in a unit
/// test with plain controllers — no yse, no interpreter.
class LogCoordinator {
  /// Subscribes [engineMessages] and [pythonEvents] into [_recorder] immediately.
  LogCoordinator({
    required this._recorder,
    required Stream<String> engineMessages,
    required Stream<EvalEvent> pythonEvents,
  }) {
    // Engine lines land tagged `engine`, at a level inferred from the text
    // (yse's stream carries no structured level).
    _engineSub = engineMessages.listen(
      (message) => _recorder.engine(message, level: engineLogLevel(message)),
    );
    // The interpreter's uncaught tracebacks arrive as [EvalStderr] frames on the
    // evaluator's event stream — the same stream the Code surface's inline strip
    // reads (design §2, "two consumers"). Log them at error level; stdout and
    // diagnostic frames are not log material.
    _pythonSub = pythonEvents.listen((event) {
      if (event is EvalStderr) _recorder.python(event.text);
    });
  }

  final LogRecorder _recorder;
  late final StreamSubscription<String> _engineSub;
  late final StreamSubscription<EvalEvent> _pythonSub;

  /// Cancels both source subscriptions. Call when the shell is torn down.
  Future<void> dispose() async {
    await _engineSub.cancel();
    await _pythonSub.cancel();
  }
}
