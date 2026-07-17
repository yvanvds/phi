import 'dart:io';

import 'package:path/path.dart' as p;

import 'journal_store.dart';

/// The production [JournalStore]: it reads and writes the `.recovery/` files of
/// an actual `.phi` folder through `dart:io` (design
/// `docs/design/project-registry.md` §5, §7 — `dart:io` is fine in this
/// non-Flutter layer).
///
/// Bound to the same [directory] as `RealProjectStore`, it owns two paths under
/// it: `.recovery/journal.jsonl` (the append-only command log) and
/// `.recovery/recovering` (the crash-loop sentinel). Every [append] and every
/// sentinel write is flushed to disk (`flush: true`) before it completes, so a
/// crash never loses an acknowledged command — the whole point of the journal
/// (§7, review decision 4: fsync per command).
class RealJournalStore implements JournalStore {
  /// Binds the store to the project [directory] (the `<name>.phi` folder); the
  /// journal and sentinel live in its `.recovery/` subfolder.
  RealJournalStore(this.directory);

  /// The `.phi` folder whose `.recovery/` corner this store manages.
  final Directory directory;

  /// The subfolder holding the journal and sentinel.
  static const String recoveryDir = '.recovery';

  /// The command journal's file name inside [recoveryDir].
  static const String journalFileName = 'journal.jsonl';

  /// The crash-recovery sentinel's file name inside [recoveryDir].
  static const String sentinelFileName = 'recovering';

  File get _journalFile =>
      File(p.join(directory.path, recoveryDir, journalFileName));

  File get _sentinelFile =>
      File(p.join(directory.path, recoveryDir, sentinelFileName));

  @override
  Future<void> append(String line) async {
    await Directory(
      p.join(directory.path, recoveryDir),
    ).create(recursive: true);
    await _journalFile.writeAsString(
      '$line\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  @override
  Future<List<String>> readLines() async {
    final file = _journalFile;
    if (!await file.exists()) return const [];
    final raw = await file.readAsString();
    return [
      for (final line in raw.split('\n'))
        if (line.trim().isNotEmpty) line,
    ];
  }

  @override
  Future<bool> hasJournal() async => (await readLines()).isNotEmpty;

  @override
  Future<void> truncate() async {
    final file = _journalFile;
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> markRecovering() async {
    await Directory(
      p.join(directory.path, recoveryDir),
    ).create(recursive: true);
    await _sentinelFile.writeAsString('', flush: true);
  }

  @override
  Future<bool> isRecovering() => _sentinelFile.exists();

  @override
  Future<void> clearRecovering() async {
    final file = _sentinelFile;
    if (await file.exists()) await file.delete();
  }
}
