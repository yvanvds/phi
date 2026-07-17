import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/commands/create_entity_command.dart';
import 'package:phi/domain/project/commands/create_group_command.dart';
import 'package:phi/domain/project/commands/move_entity_command.dart';
import 'package:phi/domain/project/commands/remove_entity_command.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/undo_scope.dart';

EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

void main() {
  late ProjectRegistry registry;

  setUp(() => registry = ProjectRegistry());
  tearDown(() => registry.dispose());

  group('CreateEntityCommand', () {
    test('apply creates the entity; revert removes it', () {
      final cmd = CreateEntityCommand(registry, addr('clip.lead'), payload: 7);
      cmd.apply();
      expect(registry.entityAt(addr('clip.lead'))?.payload, 7);
      cmd.revert();
      expect(registry.contains(addr('clip.lead')), isFalse);
    });

    test('entitiesTouched names the created address', () {
      final cmd = CreateEntityCommand(registry, addr('clip.lead'));
      expect(cmd.entitiesTouched, {addr('clip.lead')});
    });

    test('toJson carries type, address and payload', () {
      final cmd = CreateEntityCommand(registry, addr('clip.lead'), payload: 7);
      expect(cmd.toJson(), {
        'type': 'create_entity',
        'address': 'clip.lead',
        'payload': 7,
      });
      expect(cmd.label, 'create clip.lead');
    });

    test('carries declared references into the index; revert clears them', () {
      final cmd = CreateEntityCommand(
        registry,
        addr('voice.bells'),
        references: {addr('mix.perc')},
      );
      cmd.apply();
      expect(registry.referrersOf(addr('mix.perc')), {addr('voice.bells')});
      expect(cmd.toJson(), {
        'type': 'create_entity',
        'address': 'voice.bells',
        'references': ['mix.perc'],
      });
      cmd.revert();
      expect(registry.referrersOf(addr('mix.perc')), isEmpty);
    });
  });

  group('RemoveEntityCommand', () {
    test('apply removes the entity; revert restores it with its payload', () {
      registry.createEntity(addr('clip.lead'), payload: 'x');
      final cmd = RemoveEntityCommand(registry, addr('clip.lead'));
      cmd.apply();
      expect(registry.contains(addr('clip.lead')), isFalse);
      cmd.revert();
      expect(registry.entityAt(addr('clip.lead'))?.payload, 'x');
    });

    test('reverting a delete of a missing entity restores nothing', () {
      final cmd = RemoveEntityCommand(registry, addr('clip.ghost'));
      cmd.apply();
      cmd.revert();
      expect(registry.contains(addr('clip.ghost')), isFalse);
    });

    test('revert restores the entity with its references in the index', () {
      registry.createEntity(
        addr('voice.bells'),
        references: {addr('mix.perc')},
      );
      final cmd = RemoveEntityCommand(registry, addr('voice.bells'));
      cmd.apply();
      expect(registry.referrersOf(addr('mix.perc')), isEmpty);
      cmd.revert();
      expect(registry.referrersOf(addr('mix.perc')), {addr('voice.bells')});
    });

    test('toJson carries type and address', () {
      final cmd = RemoveEntityCommand(registry, addr('clip.lead'));
      expect(cmd.toJson(), {'type': 'remove_entity', 'address': 'clip.lead'});
    });
  });

  group('MoveEntityCommand', () {
    test('apply moves/renames; revert puts it back', () {
      registry.createEntity(addr('clip.a'), payload: 1);
      final cmd = MoveEntityCommand(registry, addr('clip.a'), addr('clip.b'));
      cmd.apply();
      expect(registry.contains(addr('clip.a')), isFalse);
      expect(registry.entityAt(addr('clip.b'))?.payload, 1);
      cmd.revert();
      expect(registry.entityAt(addr('clip.a'))?.payload, 1);
      expect(registry.contains(addr('clip.b')), isFalse);
    });

    test('entitiesTouched names both endpoints', () {
      final cmd = MoveEntityCommand(registry, addr('clip.a'), addr('clip.b'));
      expect(cmd.entitiesTouched, {addr('clip.a'), addr('clip.b')});
    });

    test('toJson carries from and to', () {
      final cmd = MoveEntityCommand(registry, addr('clip.a'), addr('clip.b'));
      expect(cmd.toJson(), {'type': 'move', 'from': 'clip.a', 'to': 'clip.b'});
    });

    test('rename refactors referents; entitiesTouched names them', () {
      registry.createEntity(addr('mix.perc'));
      registry.createEntity(
        addr('voice.bells'),
        references: {addr('mix.perc')},
      );
      final cmd = MoveEntityCommand(
        registry,
        addr('mix.perc'),
        addr('mix.percussion'),
      );

      cmd.apply();
      expect(registry.referencesOf(addr('voice.bells')), {
        addr('mix.percussion'),
      });
      // The rewritten referent joins the two endpoints for dirty-tracking.
      expect(cmd.entitiesTouched, {
        addr('mix.perc'),
        addr('mix.percussion'),
        addr('voice.bells'),
      });

      cmd.revert();
      expect(registry.referencesOf(addr('voice.bells')), {addr('mix.perc')});
    });
  });

  group('CreateGroupCommand', () {
    test('apply creates the group; revert removes it', () {
      final cmd = CreateGroupCommand(registry, addr('clip.drums'));
      cmd.apply();
      expect(registry.groupAt(addr('clip.drums')), isNotNull);
      cmd.revert();
      expect(registry.contains(addr('clip.drums')), isFalse);
    });

    test('revert leaves a pre-existing group alone (idempotent create)', () {
      registry.createGroup(addr('clip.drums'));
      final cmd = CreateGroupCommand(registry, addr('clip.drums'));
      cmd.apply();
      cmd.revert();
      // The group this command did not create survives the undo.
      expect(registry.groupAt(addr('clip.drums')), isNotNull);
    });
  });

  group('through an UndoScope', () {
    test('registry mutations are undoable and redoable via the scope', () {
      final scope = UndoScope(id: 'test');
      addTearDown(scope.dispose);

      scope.run(CreateEntityCommand(registry, addr('clip.a'), payload: 1));
      scope.run(MoveEntityCommand(registry, addr('clip.a'), addr('clip.b')));
      expect(registry.entityAt(addr('clip.b'))?.payload, 1);

      scope.undo(); // undo the move
      expect(registry.entityAt(addr('clip.a'))?.payload, 1);
      expect(registry.contains(addr('clip.b')), isFalse);

      scope.undo(); // undo the create
      expect(registry.contains(addr('clip.a')), isFalse);

      scope.redo(); // redo the create
      expect(registry.entityAt(addr('clip.a'))?.payload, 1);
    });

    test('a rename-refactor is one undoable step across referents', () {
      final scope = UndoScope(id: 'test');
      addTearDown(scope.dispose);

      registry.createEntity(addr('mix.perc'));
      registry.createEntity(
        addr('voice.bells'),
        references: {addr('mix.perc')},
      );

      scope.run(
        MoveEntityCommand(registry, addr('mix.perc'), addr('mix.percussion')),
      );
      expect(registry.referencesOf(addr('voice.bells')), {
        addr('mix.percussion'),
      });

      scope.undo(); // one step undoes the whole refactor
      expect(registry.referencesOf(addr('voice.bells')), {addr('mix.perc')});

      scope.redo();
      expect(registry.referencesOf(addr('voice.bells')), {
        addr('mix.percussion'),
      });
    });
  });
}
