import 'dart:convert';

import '../project_command.dart';
import '../store/journal_store.dart';

/// The command-level view of the append-only journal (design
/// `docs/design/project-registry.md` §7) — it turns [ProjectCommand]s into the
/// JSON lines a [JournalStore] persists, and back.
///
/// Every applied command is [record]ed as one fsynced line; a successful save
/// [truncate]s the whole journal. The `recovering` sentinel is threaded through
/// here too so the crash-loop guard (§7) reads and writes it through one object.
/// The write side (this class) is what the project-lifecycle layer will call on
/// each command and each save; the read/replay side is [CrashRecovery].
class CommandJournal {
  /// Builds a journal over the persistence [store].
  CommandJournal(this._store);

  final JournalStore _store;

  /// Appends [command] to the journal as one JSON line, flushed to disk before
  /// completing (§7). Records the command's *forward* form — the same
  /// `toJson` a menu or the undo stack would serialise.
  Future<void> record(ProjectCommand command) =>
      _store.append(jsonEncode(command.toJson()));

  /// The journaled command maps in application order — the input to replay.
  Future<List<Map<String, Object?>>> entries() async => [
    for (final line in await _store.readLines())
      jsonDecode(line) as Map<String, Object?>,
  ];

  /// Whether the journal holds any unsaved commands (a crash left work behind).
  Future<bool> hasEntries() => _store.hasJournal();

  /// Clears the journal after a successful save (§7).
  Future<void> truncate() => _store.truncate();

  /// Marks a recovery as underway (writes the sentinel, §7).
  Future<void> markRecovering() => _store.markRecovering();

  /// Whether a prior recovery is still marked in progress — the crash-loop
  /// signal (§7).
  Future<bool> isRecovering() => _store.isRecovering();

  /// Clears the recovery sentinel — a recovery finished cleanly (§7).
  Future<void> clearRecovering() => _store.clearRecovering();
}
