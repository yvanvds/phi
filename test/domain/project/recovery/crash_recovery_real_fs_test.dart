@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:phi/domain/project/commands/create_entity_command.dart';
import 'package:phi/domain/project/commands/create_group_command.dart';
import 'package:phi/domain/project/commands/move_entity_command.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/recovery/command_journal.dart';
import 'package:phi/domain/project/recovery/crash_recovery.dart';
import 'package:phi/domain/project/recovery/recovery_offer.dart';
import 'package:phi/domain/project/store/project_manifest.dart';
import 'package:phi/domain/project/store/project_snapshot.dart';
import 'package:phi/domain/project/store/real_journal_store.dart';
import 'package:phi/domain/project/store/real_project_store.dart';

EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

/// The Phase-2 exit loop's persistence leg end-to-end on a *real* `.phi` folder:
/// new project → edit → save → crash mid-edit → reopen → recover from the
/// journal → identical state (epic #117 "Done when"). No UI is wired yet
/// (project-lifecycle UI is a later epic issue), so this real-filesystem
/// round-trip — real save, real fsynced journal, real sentinel, real replay — is
/// the strongest end-to-end exercise available for the recovery seam.
void main() {
  late Directory tempDir;
  late Directory projectDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('phi_recovery_test_');
    projectDir = Directory(p.join(tempDir.path, 'my_set.phi'));
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  ProjectSnapshot snapshotOf(
    ProjectRegistry registry, {
    ProjectManifest manifest = const ProjectManifest(name: 'my_set'),
  }) => ProjectSnapshot(manifest: manifest, registry: registry);

  test('recovers the exact pre-crash state from the journal', () async {
    // New project with a clean first save.
    final store = RealProjectStore(projectDir);
    final live = ProjectRegistry();
    live.createEntity(addr('mix.perc'));
    live.createEntity(addr('voice.bells'), references: {addr('mix.perc')});
    await store.save(snapshotOf(live));

    // Edits after the save — each applied live and journaled (fsynced), but the
    // save above predates them. Then the process "crashes": `live` is lost.
    final journal = CommandJournal(RealJournalStore(projectDir));
    final edits = <ProjectCommand>[
      CreateEntityCommand(live, addr('clip.b')),
      MoveEntityCommand(live, addr('mix.perc'), addr('mix.percussion')),
    ];
    for (final command in edits) {
      command.apply();
      await journal.record(command);
    }

    // Reopen: fresh stores over the same folder find the journal and recover.
    final recovery = CrashRecovery(
      store: RealProjectStore(projectDir),
      journal: CommandJournal(RealJournalStore(projectDir)),
    );
    expect(
      await recovery.detect(),
      const RecoveryOffer(entryCount: 2, crashLoop: false),
    );

    final recovered = await recovery.recover(RecoveryChoice.replayAll);

    // Identical to the live registry at the moment of the crash — including the
    // rename-is-refactor rewrite of voice.bells' reference.
    expect(recovered.registry.entityAt(addr('clip.b')), isNotNull);
    expect(recovered.registry.entityAt(addr('mix.perc')), isNull);
    expect(recovered.registry.entityAt(addr('mix.percussion')), isNotNull);
    expect(recovered.registry.referencesOf(addr('voice.bells')), {
      addr('mix.percussion'),
    });

    // Save the recovered state and resolve — back to a known-good point with an
    // empty journal and no sentinel, so the next launch finds nothing to do.
    await recovery.store.save(
      snapshotOf(recovered.registry, manifest: recovered.manifest),
    );
    await recovery.resolve();
    expect(await recovery.detect(), isNull);
    expect(await RealJournalStore(projectDir).isRecovering(), isFalse);
  });

  test(
    'a crash-loop is flagged and replay-to-previous degrades gracefully',
    () async {
      // A saved project plus two journaled-but-unsaved edits; the last one is the
      // suspected poison.
      final store = RealProjectStore(projectDir);
      final live = ProjectRegistry()..createEntity(addr('clip.a'));
      await store.save(snapshotOf(live));

      final journal = CommandJournal(RealJournalStore(projectDir));
      for (final command in <ProjectCommand>[
        CreateEntityCommand(live, addr('clip.b')),
        CreateGroupCommand(live, addr('clip.poison')),
      ]) {
        command.apply();
        await journal.record(command);
      }
      // A prior replay started but never finished: the sentinel is still on disk.
      await RealJournalStore(projectDir).markRecovering();

      final recovery = CrashRecovery(
        store: RealProjectStore(projectDir),
        journal: CommandJournal(RealJournalStore(projectDir)),
      );
      final offer = await recovery.detect();
      expect(offer, isNotNull);
      expect(offer!.crashLoop, isTrue);
      expect(offer.entryCount, 2);

      // Walk back over the last edit to escape the loop.
      final recovered = await recovery.recover(RecoveryChoice.replayToPrevious);
      expect(recovered.registry.entityAt(addr('clip.b')), isNotNull);
      expect(recovered.registry.groupAt(addr('clip.poison')), isNull);
    },
  );

  test('skipping the journal opens the last clean save', () async {
    final store = RealProjectStore(projectDir);
    final live = ProjectRegistry()..createEntity(addr('clip.a'));
    await store.save(snapshotOf(live));

    final journal = CommandJournal(RealJournalStore(projectDir));
    final command = CreateEntityCommand(live, addr('clip.b'))..apply();
    await journal.record(command);

    final recovery = CrashRecovery(
      store: RealProjectStore(projectDir),
      journal: CommandJournal(RealJournalStore(projectDir)),
    );
    final recovered = await recovery.recover(RecoveryChoice.skipJournal);

    expect(recovered.registry.entityAt(addr('clip.a')), isNotNull);
    expect(recovered.registry.entityAt(addr('clip.b')), isNull);
  });
}
