/// Abstract port for running a chunk of Python source inside the Phi
/// runtime.
///
/// The scaffold lands with a no-op default ([NoOpCodeEvaluator]); a real
/// kernel — embedded in `yse` (phi-vision.md §5), a long-lived Python
/// subprocess, or a `dart:ffi` binding to `libpython` — slots in here
/// without touching the editor surface. The choice between those three
/// is open and tracked in phi-vision.md §6 ("Hot-reload semantics for
/// Python").
abstract interface class CodeEvaluator {
  /// Evaluate [source] (one block, typically returned by
  /// `splitIntoBlocks`). The future completes once the runtime accepts
  /// the chunk; a `false` outcome means the source was rejected
  /// (compile/runtime error). Streaming output, if any, arrives on
  /// [events].
  Future<EvalOutcome> evaluate(String source);

  /// Broadcast stream of side-channel frames — stdout lines, stderr
  /// lines, diagnostic messages — produced by [evaluate]. The no-op
  /// implementation emits nothing. Subscribers should expect a
  /// broadcast stream: late joiners miss earlier frames.
  Stream<EvalEvent> get events;

  /// Release any runtime resources (subprocess, FFI handles, …). Safe
  /// to call multiple times.
  Future<void> dispose();
}

/// Result of a single `evaluate` call. Successful evaluation sets [ok]
/// to `true` and leaves [error] null. A rejected chunk carries a short
/// human-readable [error]; full tracebacks arrive over [CodeEvaluator.events].
class EvalOutcome {
  const EvalOutcome.ok() : ok = true, error = null;
  const EvalOutcome.failed(this.error) : ok = false;

  final bool ok;
  final String? error;
}

/// One frame on the [CodeEvaluator.events] stream.
sealed class EvalEvent {
  const EvalEvent();
}

class EvalStdout extends EvalEvent {
  const EvalStdout(this.text);
  final String text;
}

class EvalStderr extends EvalEvent {
  const EvalStderr(this.text);
  final String text;
}

class EvalDiagnostic extends EvalEvent {
  const EvalDiagnostic(this.message);
  final String message;
}
