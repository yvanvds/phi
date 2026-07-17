import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_entity.dart';
import 'package:phi/domain/project/registry_error.dart';
import 'package:phi/domain/project/registry_exception.dart';
import 'package:phi/domain/project/registry_group.dart';

EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

Matcher throwsRegistry(RegistryError error) =>
    throwsA(isA<RegistryException>().having((e) => e.error, 'error', error));

void main() {
  late ProjectRegistry registry;
  var notifications = 0;

  setUp(() {
    registry = ProjectRegistry();
    notifications = 0;
    registry.addListener(() => notifications++);
  });

  tearDown(() => registry.dispose());

  group('createEntity', () {
    test('creates a top-level entity and notifies', () {
      final entity = registry.createEntity(addr('clip.lead_line'), payload: 42);
      expect(entity.name, 'lead_line');
      expect(entity.kind, 'clip');
      expect(entity.payload, 42);
      expect(registry.entityAt(addr('clip.lead_line')), same(entity));
      expect(registry.contains(addr('clip.lead_line')), isTrue);
      expect(notifications, 1);
      expect(registry.version, 1);
    });

    test('auto-creates ancestor groups', () {
      registry.createEntity(addr('clip.drums.fills.intro_fill'));
      expect(registry.groupAt(addr('clip.drums')), isNotNull);
      expect(registry.groupAt(addr('clip.drums.fills')), isNotNull);
      expect(registry.entityAt(addr('clip.drums.fills.intro_fill')), isNotNull);
    });

    test('registers the kind namespace', () {
      registry.createEntity(addr('clip.a'));
      expect(registry.kinds, contains('clip'));
    });

    test('rejects a duplicate entity', () {
      registry.createEntity(addr('clip.a'));
      expect(
        () => registry.createEntity(addr('clip.a')),
        throwsRegistry(RegistryError.duplicateName),
      );
    });

    test('rejects an entity clashing with a group of the same name', () {
      registry.createGroup(addr('clip.drums'));
      expect(
        () => registry.createEntity(addr('clip.drums')),
        throwsRegistry(RegistryError.groupEntityClash),
      );
    });

    test('rejects a path running through an existing entity', () {
      registry.createEntity(addr('clip.drums'));
      expect(
        () => registry.createEntity(addr('clip.drums.intro')),
        throwsRegistry(RegistryError.groupEntityClash),
      );
    });

    test('a rejected create leaves the tree unchanged (transactional)', () {
      registry.createEntity(addr('clip.drums'));
      final before = registry.version;
      expect(
        () => registry.createEntity(addr('clip.drums.a.b.c')),
        throwsRegistry(RegistryError.groupEntityClash),
      );
      // No stray groups created along the way, and no notification.
      expect(registry.groupAt(addr('clip.drums')), isNull); // still an entity
      expect(registry.nodeAt(addr('clip.drums.a')), isNull);
      expect(registry.version, before);
    });
  });

  group('createGroup', () {
    test('creates a group and notifies', () {
      final group = registry.createGroup(addr('clip.drums'));
      expect(group.name, 'drums');
      expect(registry.groupAt(addr('clip.drums')), same(group));
      expect(notifications, 1);
    });

    test('is idempotent for an existing group — no second notify', () {
      final first = registry.createGroup(addr('clip.drums'));
      notifications = 0;
      final second = registry.createGroup(addr('clip.drums'));
      expect(second, same(first));
      expect(notifications, 0);
    });

    test('rejects a group clashing with an entity', () {
      registry.createEntity(addr('clip.drums'));
      expect(
        () => registry.createGroup(addr('clip.drums')),
        throwsRegistry(RegistryError.groupEntityClash),
      );
    });
  });

  group('queries', () {
    test('missing lookups return null / false, never throw', () {
      expect(registry.nodeAt(addr('clip.nope')), isNull);
      expect(registry.entityAt(addr('clip.nope')), isNull);
      expect(registry.groupAt(addr('clip.nope')), isNull);
      expect(registry.contains(addr('clip.nope')), isFalse);
    });

    test('entityAt returns null when a group sits there', () {
      registry.createGroup(addr('clip.drums'));
      expect(registry.entityAt(addr('clip.drums')), isNull);
    });

    test('groupAt returns null when an entity sits there', () {
      registry.createEntity(addr('clip.lead'));
      expect(registry.groupAt(addr('clip.lead')), isNull);
    });
  });

  group('listing', () {
    test('childrenOfKind lists top-level nodes in insertion order', () {
      registry.createGroup(addr('clip.drums'));
      registry.createEntity(addr('clip.lead'));
      registry.createEntity(addr('clip.bass'));
      expect(registry.childrenOfKind('clip').map((n) => n.name), [
        'drums',
        'lead',
        'bass',
      ]);
    });

    test('childrenOfKind is empty for an unknown kind', () {
      expect(registry.childrenOfKind('ghost'), isEmpty);
    });

    test('childrenOfGroup lists a group\'s direct children', () {
      registry.createEntity(addr('clip.drums.a'));
      registry.createEntity(addr('clip.drums.b'));
      registry.createGroup(addr('clip.drums.sub'));
      expect(registry.childrenOfGroup(addr('clip.drums')).map((n) => n.name), [
        'a',
        'b',
        'sub',
      ]);
    });

    test('childrenOfGroup is empty for a missing group', () {
      expect(registry.childrenOfGroup(addr('clip.ghost')), isEmpty);
    });

    test('childrenOfGroup is empty when an entity sits at the address', () {
      registry.createEntity(addr('clip.lead'));
      expect(registry.childrenOfGroup(addr('clip.lead')), isEmpty);
    });
  });

  group('remove', () {
    test('removes an entity and notifies', () {
      registry.createEntity(addr('clip.lead'));
      notifications = 0;
      expect(registry.remove(addr('clip.lead')), isTrue);
      expect(registry.contains(addr('clip.lead')), isFalse);
      expect(notifications, 1);
    });

    test('removes a group and its whole subtree', () {
      registry.createEntity(addr('clip.drums.a'));
      registry.createEntity(addr('clip.drums.sub.b'));
      expect(registry.remove(addr('clip.drums')), isTrue);
      expect(registry.contains(addr('clip.drums')), isFalse);
      expect(registry.contains(addr('clip.drums.a')), isFalse);
      expect(registry.contains(addr('clip.drums.sub.b')), isFalse);
    });

    test('is a tolerant no-op for a missing target', () {
      expect(registry.remove(addr('clip.ghost')), isFalse);
      expect(notifications, 0);
    });

    test('is a no-op when the path runs through an entity', () {
      registry.createEntity(addr('clip.lead'));
      notifications = 0;
      expect(registry.remove(addr('clip.lead.nope')), isFalse);
      expect(notifications, 0);
    });
  });

  group('move', () {
    test('reparents an entity, preserving object identity and payload', () {
      final original = registry.createEntity(addr('clip.a'), payload: 'x');
      registry.createGroup(addr('clip.drums'));
      notifications = 0;

      registry.move(addr('clip.a'), addr('clip.drums.a'));

      expect(registry.contains(addr('clip.a')), isFalse);
      final moved = registry.entityAt(addr('clip.drums.a'));
      expect(moved, same(original)); // same name → object reused
      expect(moved!.payload, 'x');
      expect(notifications, 1);
    });

    test('renames on move (new leaf name), rebuilding the node', () {
      final original = registry.createEntity(addr('clip.a'), payload: 7);
      registry.move(addr('clip.a'), addr('clip.b'));

      expect(registry.contains(addr('clip.a')), isFalse);
      final moved = registry.entityAt(addr('clip.b'));
      expect(moved, isNotNull);
      expect(moved!.name, 'b');
      expect(moved.payload, 7);
      expect(moved, isNot(same(original)));
    });

    test('auto-creates destination ancestor groups', () {
      registry.createEntity(addr('clip.a'));
      registry.move(addr('clip.a'), addr('clip.deep.nest.a'));
      expect(registry.groupAt(addr('clip.deep.nest')), isNotNull);
      expect(registry.entityAt(addr('clip.deep.nest.a')), isNotNull);
    });

    test('moves a group with its whole subtree', () {
      registry.createEntity(addr('clip.drums.a'));
      registry.createEntity(addr('clip.drums.sub.b'));
      registry.createGroup(addr('clip.percussion'));

      registry.move(addr('clip.drums'), addr('clip.percussion.drums'));

      expect(registry.contains(addr('clip.drums')), isFalse);
      expect(registry.entityAt(addr('clip.percussion.drums.a')), isNotNull);
      expect(registry.entityAt(addr('clip.percussion.drums.sub.b')), isNotNull);
    });

    test('moving onto its own address is a no-op', () {
      registry.createEntity(addr('clip.a'));
      notifications = 0;
      registry.move(addr('clip.a'), addr('clip.a'));
      expect(registry.contains(addr('clip.a')), isTrue);
      expect(notifications, 0);
    });

    test('rejects a cross-kind move', () {
      registry.createEntity(addr('clip.a'));
      expect(
        () => registry.move(addr('clip.a'), addr('mix.a')),
        throwsRegistry(RegistryError.crossKindMove),
      );
    });

    test('rejects moving a missing node', () {
      expect(
        () => registry.move(addr('clip.ghost'), addr('clip.x')),
        throwsRegistry(RegistryError.notFound),
      );
    });

    test('rejects moving a group into its own subtree', () {
      registry.createEntity(addr('clip.drums.a'));
      expect(
        () => registry.move(addr('clip.drums'), addr('clip.drums.sub')),
        throwsRegistry(RegistryError.moveIntoDescendant),
      );
    });

    test('rejects a move onto an occupied destination', () {
      registry.createEntity(addr('clip.a'));
      registry.createEntity(addr('clip.b'));
      expect(
        () => registry.move(addr('clip.a'), addr('clip.b')),
        throwsRegistry(RegistryError.duplicateName),
      );
    });

    test('rejects a move whose destination clashes group-vs-entity', () {
      registry.createGroup(addr('clip.a'));
      registry.createEntity(addr('clip.b'));
      expect(
        () => registry.move(addr('clip.a'), addr('clip.b')),
        throwsRegistry(RegistryError.groupEntityClash),
      );
    });

    test('a rejected move leaves the source in place (transactional)', () {
      registry.createEntity(addr('clip.a'));
      registry.createEntity(addr('clip.b'));
      final before = registry.version;
      expect(
        () => registry.move(addr('clip.a'), addr('clip.b')),
        throwsRegistry(RegistryError.duplicateName),
      );
      expect(registry.entityAt(addr('clip.a')), isNotNull);
      expect(registry.version, before);
    });
  });

  group('watch (ChangeNotifier)', () {
    test('multiple mutations bump version and fire per change', () {
      registry.createEntity(addr('clip.a'));
      registry.createEntity(addr('clip.b'));
      registry.remove(addr('clip.a'));
      expect(registry.version, 3);
      expect(notifications, 3);
    });

    test('node types are surfaced for pattern-matching', () {
      registry.createGroup(addr('clip.drums'));
      registry.createEntity(addr('clip.lead'));
      final children = registry.childrenOfKind('clip');
      expect(children.whereType<RegistryGroup>().map((g) => g.name), ['drums']);
      expect(children.whereType<RegistryEntity>().map((e) => e.name), ['lead']);
    });
  });
}
