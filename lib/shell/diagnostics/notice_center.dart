import '../../core/clock.dart';
import '../../domain/log/log_level.dart';
import '../../domain/log/log_recorder.dart';
import '../../domain/log/log_store.dart';
import '../../domain/log/session_log.dart';
import 'toast_controller.dart';

/// The one implementation of every design's "surfaced notice" (design
/// `docs/design/diagnostics.md` §3): a single [notice] call **shows a transient
/// toast and writes a log entry**, so nothing user-facing ever vanishes without
/// a trace.
///
/// It composes a [LogRecorder] (the app-source log half) with a [ToastController]
/// (the transient half). Shipped ad-hoc notice sites — the audio device
/// fallback, the state / patch degradation paths — retrofit onto this channel:
/// the shell listens to each one and calls [notice].
class NoticeCenter {
  /// Binds the channel to its [recorder] and [toasts]. [ownsStore] records
  /// whether [dispose] should also dispose the underlying [LogStore] (true when
  /// this center created it, false when one was handed in to be shared).
  NoticeCenter({
    required this.recorder,
    required this.toasts,
    this.ownsStore = false,
  });

  /// Builds a ready-to-use center over a fresh [ToastController] and a
  /// [LogRecorder]. Pass an existing [store] to share the log with another
  /// consumer (e.g. the log panel, #270); otherwise one is created and owned
  /// here. A [sessionLog] wires the session-file mirror; [clock] and
  /// [toastDuration] tune stamping and how long a toast lingers.
  factory NoticeCenter.build({
    LogStore? store,
    SessionLog? sessionLog,
    Clock clock = const SystemClock(),
    Duration toastDuration = const Duration(seconds: 4),
  }) {
    final resolvedStore = store ?? LogStore();
    return NoticeCenter(
      recorder: LogRecorder(
        store: resolvedStore,
        sessionLog: sessionLog,
        clock: clock,
      ),
      toasts: ToastController(displayDuration: toastDuration),
      ownsStore: store == null,
    );
  }

  /// The write path the notice's log half goes through.
  final LogRecorder recorder;

  /// The transient-toast state the overlay renders.
  final ToastController toasts;

  /// Whether [dispose] also disposes [log].
  final bool ownsStore;

  /// The unified log the notice entries (and every other source) land in — the
  /// buffer the log panel (#270) will read.
  LogStore get log => recorder.store;

  /// Surfaces [message] (design §3): a toast **and** an app-sourced log entry at
  /// [level]. Errors pass [LogLevel.error]; they toast red and badge in the
  /// status bar until the panel is opened.
  void notice(String message, {LogLevel level = LogLevel.info}) {
    recorder.app(message, level: level);
    toasts.show(message, level);
  }

  /// Releases the toast controller (and the log store when this center owns it).
  void dispose() {
    toasts.dispose();
    if (ownsStore) log.dispose();
  }
}
