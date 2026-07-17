import 'package:phi/domain/project/store/journal_store.dart';

/// In-memory [JournalStore] for tests — the same Real/Fake split as
/// `FakeProjectStore`.
///
/// Keeps the journal as a plain list of [lines] and the sentinel as a bool, so a
/// record/replay round-trip runs without touching the filesystem. [appendCount]
/// lets a test assert one fsynced write per command (§7), and [lines]/[recovering]
/// are exposed so a test can seed a pre-crash journal or inspect what was written.
class FakeJournalStore implements JournalStore {
  /// The journal's records, in write order.
  final List<String> lines = [];

  /// Whether the `recovering` sentinel is set.
  bool recovering = false;

  /// How many times [append] has been called — one per journaled command.
  int appendCount = 0;

  @override
  Future<void> append(String line) async {
    appendCount++;
    lines.add(line);
  }

  @override
  Future<List<String>> readLines() async => List.of(lines);

  @override
  Future<bool> hasJournal() async => lines.isNotEmpty;

  @override
  Future<void> truncate() async => lines.clear();

  @override
  Future<void> markRecovering() async => recovering = true;

  @override
  Future<bool> isRecovering() async => recovering;

  @override
  Future<void> clearRecovering() async => recovering = false;
}
