import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/code/code_library.dart';
import 'package:phi/domain/code/code_script.dart';
import 'package:phi/domain/project/commands/create_entity_command.dart';
import 'package:phi/domain/project/commands/move_entity_command.dart';
import 'package:phi/domain/project/commands/remove_entity_command.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/project_manifest.dart';
import 'package:phi/domain/project/store/project_snapshot.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';

import '../project/test_doubles/fake_project_store.dart';

void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  String sourceOf(ProjectRegistry registry, String dotted) {
    final payload = registry.entityAt(addr(dotted))!.payload;
    if (payload is CodeScript) return payload.source;
    return CodeScript.fromJson((payload! as Map).cast()).source;
  }

  ProjectSnapshot snapshotOf(ProjectRegistry registry) => ProjectSnapshot(
    manifest: const ProjectManifest(
      name: 'set',
      tempo: 120,
      sceneName: 'intro',
    ),
    registry: registry,
  );

  test('newScript creates an empty script at a slugged, unique address', () {
    final registry = ProjectRegistry();
    addTearDown(registry.dispose);
    final library = CodeLibrary(registry);

    library.newScript(name: 'Lead Riff').apply();
    library.newScript(name: 'Lead Riff').apply(); // collides → suffixed

    expect(registry.contains(addr('code.lead_riff')), isTrue);
    expect(registry.contains(addr('code.lead_riff_2')), isTrue);
    expect(sourceOf(registry, 'code.lead_riff'), isEmpty);
  });

  test('duplicate copies the source to <name>_copy beside it', () {
    final registry = ProjectRegistry();
    addTearDown(registry.dispose);
    registry.createEntity(
      addr('code.a'),
      payload: const CodeScript(source: 'note(60)\n').toJson(),
    );
    final library = CodeLibrary(registry);

    library.duplicate(addr('code.a')).apply();

    expect(registry.contains(addr('code.a_copy')), isTrue);
    expect(sourceOf(registry, 'code.a_copy'), 'note(60)\n');
  });

  test('duplicate of a missing script throws', () {
    final registry = ProjectRegistry();
    addTearDown(registry.dispose);
    expect(
      () => CodeLibrary(registry).duplicate(addr('code.nope')),
      throwsArgumentError,
    );
  });

  test('new / duplicate commands revert cleanly (undo)', () {
    final registry = ProjectRegistry();
    addTearDown(registry.dispose);
    registry.createEntity(
      addr('code.a'),
      payload: const CodeScript(source: 'x = 1\n').toJson(),
    );
    final library = CodeLibrary(registry);

    final commands = <CreateEntityCommand>[
      library.newScript(name: 'idea'),
      library.duplicate(addr('code.a')),
    ];
    for (final command in commands) {
      command.apply();
      expect(registry.contains(command.address), isTrue);
    }
    for (final command in commands.reversed) {
      command.revert();
      expect(registry.contains(command.address), isFalse);
    }
    expect(registry.contains(addr('code.a')), isTrue);
  });

  group('payload round-trips through save/load byte-identical', () {
    // The epic's "Done when": a saved script reopens byte-identical.
    const tricky =
        '# phi · scratch "quoted"\n'
        'x = "λ ∆ 🎹"\n'
        "print('done')\n\n";

    test('a saved script reopens with its source verbatim', () async {
      final registry = ProjectRegistry();
      seedDefaultProject(registry); // seeds code.scratch too
      CodeLibrary(registry).newScript(name: 'riff').apply();
      // Author some tricky content into the new script.
      registry.updateEntityPayload(
        addr('code.riff'),
        const CodeScript(source: tricky).toJson(),
      );

      final store = FakeProjectStore(codecs: defaultEntityCodecs());
      await store.save(snapshotOf(registry));
      final loaded = await store.load();
      addTearDown(loaded.registry.dispose);

      // Byte-identical: the exact source came back.
      expect(sourceOf(loaded.registry, 'code.riff'), tricky);
      // The seeded scratch script survived the round-trip too.
      expect(registry.contains(addr('code.scratch')), isTrue);
      expect(loaded.registry.contains(addr('code.scratch')), isTrue);
      expect(
        sourceOf(loaded.registry, 'code.scratch'),
        sourceOf(registry, 'code.scratch'),
      );

      registry.dispose();
    });

    test('rename is a move that keeps the source and undoes', () {
      final registry = ProjectRegistry();
      addTearDown(registry.dispose);
      registry.createEntity(
        addr('code.a'),
        payload: const CodeScript(source: tricky).toJson(),
      );

      final command = MoveEntityCommand(
        registry,
        addr('code.a'),
        addr('code.b'),
      );
      command.apply();
      expect(registry.contains(addr('code.a')), isFalse);
      expect(sourceOf(registry, 'code.b'), tricky);

      command.revert();
      expect(sourceOf(registry, 'code.a'), tricky);
    });

    test('delete round-trips through undo, restoring the source', () {
      final registry = ProjectRegistry();
      addTearDown(registry.dispose);
      registry.createEntity(
        addr('code.a'),
        payload: const CodeScript(source: tricky).toJson(),
      );

      final command = RemoveEntityCommand(registry, addr('code.a'));
      command.apply();
      expect(registry.contains(addr('code.a')), isFalse);

      command.revert();
      expect(sourceOf(registry, 'code.a'), tricky);
    });
  });
}
