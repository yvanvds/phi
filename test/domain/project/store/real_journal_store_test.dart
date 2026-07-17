@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:phi/domain/project/store/real_journal_store.dart';

/// Exercises the journal I/O against a *real* `.recovery/` folder on disk — the
/// strongest exercise for a data-layer seam with no UI. It drives
/// `RealJournalStore`'s `dart:io` path (real append, real fsync, real sentinel
/// files), which the in-memory fake never touches.
void main() {
  late Directory tempDir;
  late Directory projectDir;
  late RealJournalStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('phi_journal_test_');
    projectDir = Directory(p.join(tempDir.path, 'my_set.phi'));
    await projectDir.create(recursive: true);
    store = RealJournalStore(projectDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  File journalFile() => File(
    p.join(
      projectDir.path,
      RealJournalStore.recoveryDir,
      RealJournalStore.journalFileName,
    ),
  );

  File sentinelFile() => File(
    p.join(
      projectDir.path,
      RealJournalStore.recoveryDir,
      RealJournalStore.sentinelFileName,
    ),
  );

  test('append writes one flushed line per call, read back in order', () async {
    expect(await store.hasJournal(), isFalse);
    expect(await store.readLines(), isEmpty);

    await store.append('{"type":"create_group","address":"clip.drums"}');
    await store.append('{"type":"create_entity","address":"clip.lead_line"}');

    // The line is on disk immediately (fsynced), not buffered until close.
    expect(await journalFile().exists(), isTrue);
    expect(await store.hasJournal(), isTrue);
    expect(await store.readLines(), [
      '{"type":"create_group","address":"clip.drums"}',
      '{"type":"create_entity","address":"clip.lead_line"}',
    ]);

    // A fresh store over the same folder reads the same journal.
    expect(await RealJournalStore(projectDir).readLines(), hasLength(2));
  });

  test('the journal file is newline-delimited JSONL', () async {
    await store.append('{"a":1}');
    await store.append('{"b":2}');
    final raw = await journalFile().readAsString();
    expect(raw, '{"a":1}\n{"b":2}\n');
  });

  test('truncate deletes the journal on a clean save', () async {
    await store.append('{"a":1}');
    await store.truncate();
    expect(await journalFile().exists(), isFalse);
    expect(await store.hasJournal(), isFalse);
    // Truncating an already-clean journal is a no-op.
    await store.truncate();
    expect(await store.hasJournal(), isFalse);
  });

  test('the recovering sentinel is created, detected and cleared', () async {
    expect(await store.isRecovering(), isFalse);

    await store.markRecovering();
    expect(await sentinelFile().exists(), isTrue);
    expect(await store.isRecovering(), isTrue);
    expect(await RealJournalStore(projectDir).isRecovering(), isTrue);

    await store.clearRecovering();
    expect(await sentinelFile().exists(), isFalse);
    expect(await store.isRecovering(), isFalse);
  });

  test('reads are blank-line tolerant', () async {
    await store.append('{"a":1}');
    // Simulate a stray blank the reader must skip.
    await journalFile().writeAsString('\n', mode: FileMode.append, flush: true);
    expect(await store.readLines(), ['{"a":1}']);
  });
}
