import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/commands/create_entity_command.dart';
import 'package:phi/domain/project/commands/create_group_command.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/recovery/command_journal.dart';
import 'package:phi/domain/project/recovery/crash_recovery.dart';
import 'package:phi/domain/project/recovery/recovery_offer.dart';
import 'package:phi/domain/project/store/project_manifest.dart';
import 'package:phi/domain/project/store/project_snapshot.dart';

import '../test_doubles/fake_journal_store.dart';
import '../test_doubles/fake_project_store.dart';

EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

void main() {
  late FakeProjectStore store;
  late FakeJournalStore journalStore;
  late CommandJournal journal;
  late CrashRecovery recovery;

  setUp(() {
    store = FakeProjectStore();
    journalStore = FakeJournalStore();
    journal = CommandJournal(journalStore);
    recovery = CrashRecovery(store: store, journal: journal);
  });

  // A saved project with `clip.a`, then two further edits journaled but never
  // saved — the state a crash-mid-edit leaves behind.
  Future<void> seedCrashMidEdit() async {
    final saved = ProjectRegistry();
    saved.createEntity(addr('clip.a'));
    await store.save(
      ProjectSnapshot(
        manifest: const ProjectManifest(name: 'set'),
        registry: saved,
      ),
    );
    // These two are applied live and journaled, but the save above predates them.
    await journal.record(CreateEntityCommand(saved, addr('clip.b')));
    await journal.record(CreateGroupCommand(saved, addr('clip.drums')));
  }

  test('detect returns null when the journal is clean', () async {
    final saved = ProjectRegistry()..createEntity(addr('clip.a'));
    await store.save(
      ProjectSnapshot(
        manifest: const ProjectManifest(name: 'set'),
        registry: saved,
      ),
    );
    expect(await recovery.detect(), isNull);
  });

  test('detect reports the unsaved command count', () async {
    await seedCrashMidEdit();
    expect(
      await recovery.detect(),
      const RecoveryOffer(entryCount: 2, crashLoop: false),
    );
  });

  test('detect flags a crash-loop when the sentinel is present', () async {
    await seedCrashMidEdit();
    await journalStore.markRecovering();
    expect(
      await recovery.detect(),
      const RecoveryOffer(entryCount: 2, crashLoop: true),
    );
  });

  test('replayAll rebuilds the exact pre-crash state', () async {
    await seedCrashMidEdit();
    final snapshot = await recovery.recover(RecoveryChoice.replayAll);

    expect(snapshot.registry.entityAt(addr('clip.a')), isNotNull);
    expect(snapshot.registry.entityAt(addr('clip.b')), isNotNull);
    expect(snapshot.registry.groupAt(addr('clip.drums')), isNotNull);
  });

  test('replayAll marks the recovering sentinel for the duration', () async {
    await seedCrashMidEdit();
    await recovery.recover(RecoveryChoice.replayAll);
    // Still set until the recovered state is saved and resolve() runs.
    expect(await journal.isRecovering(), isTrue);
  });

  test('replayToPrevious walks back over the last edit', () async {
    await seedCrashMidEdit();
    final snapshot = await recovery.recover(RecoveryChoice.replayToPrevious);

    expect(snapshot.registry.entityAt(addr('clip.b')), isNotNull);
    // The last journaled command (create clip.drums) is skipped.
    expect(snapshot.registry.groupAt(addr('clip.drums')), isNull);
  });

  test('skipJournal opens the clean save untouched, no sentinel', () async {
    await seedCrashMidEdit();
    final snapshot = await recovery.recover(RecoveryChoice.skipJournal);

    expect(snapshot.registry.entityAt(addr('clip.a')), isNotNull);
    expect(snapshot.registry.entityAt(addr('clip.b')), isNull);
    expect(await journal.isRecovering(), isFalse);
  });

  test('resolve truncates the journal and clears the sentinel', () async {
    await seedCrashMidEdit();
    await recovery.recover(RecoveryChoice.replayAll);
    await recovery.resolve();

    expect(await journal.hasEntries(), isFalse);
    expect(await journal.isRecovering(), isFalse);
    // Nothing left to recover on the next launch.
    expect(await recovery.detect(), isNull);
  });
}
