/// The engine's log stream as a plain-Dart seam (design
/// `docs/design/diagnostics.md` §2).
///
/// `PhiEngine` exposes the engine's log messages through this port rather than
/// touching `package:yse` above the bridge. The production
/// [RealEngineLogSource] forwards yse's `Log.messages`; a bare engine (tests)
/// gets [NoOpEngineLogSource], an empty stream. yse emits log lines as plain
/// strings with no structured level, so the level is classified downstream
/// (`engineLogLevel`).
abstract interface class EngineLogSource {
  /// The engine's log lines, newest as they arrive. Subscribing to the real
  /// source replaces yse's own file sink — our session file is the sink now
  /// (design §2).
  Stream<String> get messages;
}

/// The default [EngineLogSource] — an empty stream, for an engine with no live
/// yse log to forward (tests, or a run before the engine is up).
class NoOpEngineLogSource implements EngineLogSource {
  /// A const no-op source.
  const NoOpEngineLogSource();

  @override
  Stream<String> get messages => const Stream<String>.empty();
}
