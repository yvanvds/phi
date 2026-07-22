/// The filesystem seam the [SessionLog] lifecycle sits on — the Real/Fake split
/// that keeps retention, crash detection, and the marker lifecycle testable
/// without touching a real disk (design `docs/design/diagnostics.md` §2, §6).
///
/// `RealLogFileStore` (`dart:io`) reads and writes `%APPDATA%/phi/logs/`; an
/// in-memory fake stands in for unit tests. The orchestration (which files to
/// prune, when a crash happened, when to write the marker) lives in [SessionLog]
/// so that logic is exercised against the fake — this interface only moves bytes.
abstract interface class LogFileStore {
  /// The names of the existing `phi-<timestamp>.log` session files, **newest
  /// first**. Excludes the clean-shutdown marker.
  Future<List<String>> sessionLogNames();

  /// Appends [line] (a single record, no trailing newline) to the session file
  /// [name], creating the file — and the logs folder — if missing.
  Future<void> appendLine(String name, String line);

  /// Deletes the session file [name], used by retention pruning. A missing file
  /// is not an error.
  Future<void> deleteSessionLog(String name);

  /// Whether the clean-shutdown marker is present.
  Future<bool> markerExists();

  /// Writes the clean-shutdown marker (its content is [note], a readable line).
  Future<void> writeMarker(String note);

  /// Deletes the clean-shutdown marker. A missing marker is not an error.
  Future<void> deleteMarker();
}
