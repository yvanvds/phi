import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/library/clip_library.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/smf/smf_writer.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/project/commands/create_entity_command.dart';
import 'package:phi/domain/project/commands/move_entity_command.dart';
import 'package:phi/domain/project/commands/remove_entity_command.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/project_manifest.dart';
import 'package:phi/domain/project/store/project_snapshot.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';

import '../../project/test_doubles/fake_project_store.dart';

/// The library epic's "Done when": each command round-trips through **save/load**
/// (the real [ProjectSerializer] via the fake store's byte map) and **undo** (the
/// journaled [CreateEntityCommand]'s `revert`). A domain-level end-to-end of the
/// persistence path — there is no library-panel UI yet (that is a later epic
/// issue), so this is the fullest flow available at this layer.
void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  ClipDocument documentOf(ProjectRegistry registry, String dotted) =>
      ClipDocument.fromJson(
        (registry.entityAt(addr(dotted))!.payload! as Map).cast(),
      );

  ProjectSnapshot snapshotOf(ProjectRegistry registry) => ProjectSnapshot(
    manifest: const ProjectManifest(
      name: 'set',
      tempo: 120,
      sceneName: 'intro',
    ),
    registry: registry,
  );

  Uint8List importedBytes() => const SmfWriter().write(
    MidiClip(
      bars: 1,
      notes: const [
        MidiNote(pitch: 48, start: 0, duration: 1, velocity: 0.9),
        MidiNote(pitch: 55, start: 1, duration: 1, velocity: 0.9),
      ],
    ),
  );

  test('new / duplicate / import all round-trip through save and load', () async {
    final registry = ProjectRegistry();
    seedDefaultProject(registry); // gives clip.phrase_a (source + chain).
    final library = ClipLibrary(registry);

    library.newClip(name: 'Fresh Idea').apply();
    library.duplicate(addr('clip.phrase_a')).apply();
    library.importFromSmf(importedBytes(), fileName: 'bass line.mid').apply();

    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    await store.save(snapshotOf(registry));
    final loaded = await store.load();
    addTearDown(loaded.registry.dispose);

    // The empty new clip survived, loop-on.
    final fresh = documentOf(loaded.registry, 'clip.fresh_idea');
    expect(fresh.source.notes, isEmpty);
    expect(fresh.loop, isTrue);

    // The duplicate carried the seed clip's whole document — its interpretation
    // chain, not just the notes.
    final copy = documentOf(loaded.registry, 'clip.phrase_a_copy');
    expect(copy.source.notes, isNotEmpty);
    expect(copy.chain, isNotEmpty);

    // The import landed at its slugged address with the decoded notes.
    final imported = documentOf(loaded.registry, 'clip.bass_line');
    expect(imported.source.notes, hasLength(2));

    registry.dispose();
  });

  test('applying then reverting the commands leaves the registry clean', () {
    final registry = ProjectRegistry();
    addTearDown(registry.dispose);
    seedDefaultProject(registry);
    final library = ClipLibrary(registry);

    final commands = <CreateEntityCommand>[
      library.newClip(name: 'idea'),
      library.duplicate(addr('clip.phrase_a')),
      library.importFromSmf(importedBytes(), fileName: 'loop.mid'),
    ];

    for (final command in commands) {
      command.apply();
      expect(registry.contains(command.address), isTrue);
    }

    // Undo LIFO — the created entities disappear, the seed is untouched.
    for (final command in commands.reversed) {
      command.revert();
      expect(registry.contains(command.address), isFalse);
    }
    expect(registry.contains(addr('clip.phrase_a')), isTrue);
  });

  group('delete and rename go through the existing registry commands', () {
    test(
      'deleting a clip round-trips through undo, restoring its document',
      () {
        final registry = ProjectRegistry();
        addTearDown(registry.dispose);
        seedDefaultProject(registry);

        final before = documentOf(registry, 'clip.phrase_a');
        final command = RemoveEntityCommand(registry, addr('clip.phrase_a'));

        command.apply();
        expect(registry.contains(addr('clip.phrase_a')), isFalse);

        command.revert();
        final after = documentOf(registry, 'clip.phrase_a');
        // The whole document — source notes and chain — came back intact.
        expect(after.source.notes, hasLength(before.source.notes.length));
        expect(after.chain, hasLength(before.chain.length));
      },
    );

    test('renaming a clip is a move that keeps its payload and undoes', () {
      final registry = ProjectRegistry();
      addTearDown(registry.dispose);
      seedDefaultProject(registry);

      final command = MoveEntityCommand(
        registry,
        addr('clip.phrase_a'),
        addr('clip.phrase_b'),
      );

      command.apply();
      expect(registry.contains(addr('clip.phrase_a')), isFalse);
      expect(documentOf(registry, 'clip.phrase_b').chain, isNotEmpty);

      command.revert();
      expect(registry.contains(addr('clip.phrase_b')), isFalse);
      expect(registry.contains(addr('clip.phrase_a')), isTrue);
    });
  });
}
