/// The append-only I/O seam behind the command journal and its crash-recovery
/// sentinel (design `docs/design/project-registry.md` §5, §7) — the same
/// Real/Fake split as [ProjectStore] and `YseGateway`.
///
/// A journal store owns the `.recovery/` corner of a `.phi` folder:
/// `journal.jsonl` (one JSON line per applied command since the last save) and
/// the `recovering` sentinel (present only while a recovery is in flight). The
/// store deals in raw *lines* and the sentinel *flag* — turning commands into
/// JSON and replaying them is the layer above (`CommandJournal`,
/// `CrashRecovery`). `RealJournalStore` (`dart:io`) writes real files, flushing
/// each append to disk; an in-memory fake keeps the same lines for tests.
///
/// **Fsync per command (§7, review decision 4).** [append] must not complete
/// until the line is on disk: a crash is exactly what the journal exists to
/// survive, so a buffered-but-lost tail would defeat it. Batching flushes only
/// pays above ~1 command/s, which manual editing never sustains.
abstract interface class JournalStore {
  /// Appends [line] as one journal record, flushing it to disk before the
  /// returned future completes (fsync per command, §7). [line] carries no
  /// trailing newline — the store adds the record separator.
  Future<void> append(String line);

  /// Every journal record in write order, or an empty list when no journal is
  /// present. Blank lines are skipped.
  Future<List<String>> readLines();

  /// Whether a non-empty journal exists — the signal that a crash left applied
  /// commands unsaved and recovery is warranted.
  Future<bool> hasJournal();

  /// Clears the journal (a successful save truncates it, §7). A no-op when no
  /// journal file exists.
  Future<void> truncate();

  /// Writes the `recovering` sentinel, marking that a recovery is underway. If
  /// the process crashes before [clearRecovering], the next launch sees the
  /// sentinel and treats the journal as a crash-loop suspect (§7).
  Future<void> markRecovering();

  /// Whether the `recovering` sentinel is present.
  Future<bool> isRecovering();

  /// Removes the `recovering` sentinel — a recovery finished cleanly. A no-op
  /// when the sentinel is absent.
  Future<void> clearRecovering();
}
