import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/commands/create_entity_command.dart';
import 'package:phi/domain/project/commands/create_group_command.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/recovery/command_journal.dart';

import '../test_doubles/fake_journal_store.dart';

EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

void main() {
  late FakeJournalStore store;
  late CommandJournal journal;

  setUp(() {
    store = FakeJournalStore();
    journal = CommandJournal(store);
  });

  test('records one fsynced line per command in order', () async {
    final registry = ProjectRegistry();
    await journal.record(CreateGroupCommand(registry, addr('clip.drums')));
    await journal.record(CreateEntityCommand(registry, addr('clip.lead_line')));

    // One append (one fsync) per command — §7, review decision 4.
    expect(store.appendCount, 2);
    final entries = await journal.entries();
    expect(entries, hasLength(2));
    expect(entries[0]['type'], 'create_group');
    expect(entries[0]['address'], 'clip.drums');
    expect(entries[1]['type'], 'create_entity');
    expect(entries[1]['address'], 'clip.lead_line');
  });

  test('hasEntries reflects whether anything is journaled', () async {
    expect(await journal.hasEntries(), isFalse);
    await journal.record(CreateGroupCommand(ProjectRegistry(), addr('mix.a')));
    expect(await journal.hasEntries(), isTrue);
  });

  test('truncate clears the journal on a clean save', () async {
    await journal.record(CreateGroupCommand(ProjectRegistry(), addr('mix.a')));
    await journal.truncate();
    expect(await journal.hasEntries(), isFalse);
    expect(await journal.entries(), isEmpty);
  });

  test('sentinel is marked, read and cleared through the journal', () async {
    expect(await journal.isRecovering(), isFalse);
    await journal.markRecovering();
    expect(await journal.isRecovering(), isTrue);
    await journal.clearRecovering();
    expect(await journal.isRecovering(), isFalse);
  });
}
