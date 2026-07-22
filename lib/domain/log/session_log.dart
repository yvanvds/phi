import '../../core/clock.dart';
import 'crash_report.dart';
import 'log_entry.dart';
import 'log_file_store.dart';

/// The session log file's lifecycle: it mirrors the [LogStore] to disk, prunes
/// old sessions, and turns the clean-shutdown marker into crash detection
/// (design `docs/design/diagnostics.md` §2, §6).
///
/// All disk access goes through the [LogFileStore] seam, so the interesting
/// logic here — retention, the marker lifecycle, crash detection — is unit-tested
/// against a fake filesystem. The lifecycle is:
///
/// 1. [boot] once at launch: it detects whether the *previous* session crashed
///    (its clean-shutdown marker was missing), removes that marker, opens a
///    fresh `phi-<timestamp>.log`, and prunes to the newest [retention] sessions.
/// 2. [append] each entry as it lands in the store (append-through).
/// 3. [close] at orderly shutdown: it writes the clean-shutdown marker, so the
///    *next* boot knows this session ended cleanly.
///
/// A session that never reaches [close] leaves no marker — the next [boot]
/// reads that absence as a crash and offers this session's log.
class SessionLog {
  /// Binds the lifecycle to its [files] seam and [clock], keeping at most
  /// [retention] session files (default 20 — the design's window).
  SessionLog({
    required this.files,
    this.clock = const SystemClock(),
    this.retention = defaultRetention,
  }) : assert(retention > 0, 'retention must be positive');

  /// The design's default number of session files to keep.
  static const int defaultRetention = 20;

  /// The filesystem seam every read/write goes through.
  final LogFileStore files;

  /// Where timestamps (file names, the marker note) come from.
  final Clock clock;

  /// How many `phi-<timestamp>.log` files to keep, newest first.
  final int retention;

  String? _currentName;

  /// The session file this run is writing to, or `null` before [boot].
  String? get currentLogName => _currentName;

  /// Opens the session for this run and reports whether the previous one
  /// crashed.
  ///
  /// The clean-shutdown marker's **absence** means the last session never
  /// reached [close] — a crash — so a non-null [CrashReport] points at the
  /// newest pre-existing log. A present marker means a clean exit; it is
  /// consumed here so that if *this* session crashes the next boot detects it.
  /// The first ever boot (no marker, no prior log) is not a crash.
  Future<CrashReport?> boot() async {
    final existing = await files.sessionLogNames(); // newest first
    final previous = existing.isEmpty ? null : existing.first;

    CrashReport? report;
    if (await files.markerExists()) {
      await files.deleteMarker(); // clean exit last time — consume the marker
    } else if (previous != null) {
      report = CrashReport(previousLogName: previous);
    }

    final now = clock.now();
    final name = 'phi-${_fileStamp(now)}.log';
    _currentName = name;
    await files.appendLine(name, '# Phi session log — ${_readable(now)}');

    // Keep the newest [retention] sessions, this fresh one included.
    final kept = <String>[name, ...existing];
    for (final stale in kept.skip(retention)) {
      await files.deleteSessionLog(stale);
    }

    return report;
  }

  /// Appends [entry] to the current session file. Must be called after [boot].
  Future<void> append(LogEntry entry) async {
    final name = _currentName;
    if (name == null) {
      throw StateError('SessionLog.append called before boot()');
    }
    await files.appendLine(name, entry.format());
  }

  /// Marks an orderly shutdown by writing the clean-shutdown marker. Idempotent.
  Future<void> close() async {
    final name = _currentName;
    final note = name == null
        ? 'clean shutdown ${_readable(clock.now())}'
        : 'clean shutdown ${_readable(clock.now())} — $name';
    await files.writeMarker(note);
  }

  /// A sortable, filesystem-safe stamp: `20260722-143355-123`. Lexicographic
  /// order equals chronological order, so names sort newest-last by string.
  static String _fileStamp(DateTime t) {
    final y = t.year.toString().padLeft(4, '0');
    final mo = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    final h = t.hour.toString().padLeft(2, '0');
    final mi = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    return '$y$mo$d-$h$mi$s-$ms';
  }

  static String _readable(DateTime t) {
    final y = t.year.toString().padLeft(4, '0');
    final mo = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    final h = t.hour.toString().padLeft(2, '0');
    final mi = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi:$s';
  }
}
