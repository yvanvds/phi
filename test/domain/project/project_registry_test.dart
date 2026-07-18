import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/reference_source.dart';
import 'package:phi/domain/project/registry_entity.dart';
import 'package:phi/domain/project/registry_error.dart';
import 'package:phi/domain/project/registry_exception.dart';
import 'package:phi/domain/project/registry_group.dart';

EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

Matcher throwsRegistry(RegistryError error) =>
    throwsA(isA<RegistryException>().having((e) => e.error, 'error', error));

/// A payload that references others by address and rewrites them structurally —
/// the stand-in for a real voice/mix payload until kinds carry their own
/// (design §4). Records how many times a rewrite occurred so tests can assert
/// the registry actually rewrote the payload, not just the declared set.
class _RefBox implements ReferenceSource {
  _RefBox(this.references, {this.rewrites = 0});

  @override
  final Set<EntityAddress> references;

  final int rewrites;

  @override
  ReferenceSource withReferenceUpdated(EntityAddress from, EntityAddress to) =>
      _RefBox(
        references.map((r) => r == from ? to : r).toSet(),
        rewrites: rewrites + 1,
      );
}

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

  group('back-reference index', () {
    test('createEntity with declared references populates the index', () {
      registry.createEntity(addr('mix.perc'));
      registry.createEntity(
        addr('voice.bells'),
        references: {addr('mix.perc')},
      );
      expect(registry.referrersOf(addr('mix.perc')), {addr('voice.bells')});
      expect(registry.referencesOf(addr('voice.bells')), {addr('mix.perc')});
    });

    test('a ReferenceSource payload supplies the references', () {
      registry.createEntity(
        addr('voice.bells'),
        payload: _RefBox({addr('mix.perc'), addr('synth.fm_bells')}),
      );
      expect(registry.referencesOf(addr('voice.bells')), {
        addr('mix.perc'),
        addr('synth.fm_bells'),
      });
      expect(registry.referrersOf(addr('mix.perc')), {addr('voice.bells')});
    });

    test('removing a referrer clears its outgoing edges', () {
      registry.createEntity(
        addr('voice.bells'),
        references: {addr('mix.perc')},
      );
      registry.remove(addr('voice.bells'));
      expect(registry.referrersOf(addr('mix.perc')), isEmpty);
    });

    test('removing a target leaves the (now dangling) incoming edge', () {
      registry.createEntity(
        addr('voice.bells'),
        references: {addr('mix.perc')},
      );
      registry.remove(addr('mix.perc'));
      // voice.bells still declares a reference to the missing mix.perc.
      expect(registry.referrersOf(addr('mix.perc')), {addr('voice.bells')});
    });

    test('setReferences replaces edges and reindexes', () {
      registry.createEntity(
        addr('voice.bells'),
        references: {addr('mix.perc')},
      );
      registry.setReferences(addr('voice.bells'), {addr('mix.master')});
      expect(registry.referrersOf(addr('mix.perc')), isEmpty);
      expect(registry.referrersOf(addr('mix.master')), {addr('voice.bells')});
    });

    test('setReferences throws when no entity is there', () {
      expect(
        () => registry.setReferences(addr('voice.ghost'), const {}),
        throwsRegistry(RegistryError.notFound),
      );
    });
  });

  group('rename / move = refactor', () {
    test('renaming a target rewrites every referent', () {
      registry.createEntity(addr('mix.perc'));
      registry.createEntity(
        addr('voice.bells'),
        references: {addr('mix.perc')},
      );
      registry.createEntity(addr('voice.tom'), references: {addr('mix.perc')});

      final rewritten = registry.move(addr('mix.perc'), addr('mix.percussion'));

      expect(rewritten, {addr('voice.bells'), addr('voice.tom')});
      expect(registry.referencesOf(addr('voice.bells')), {
        addr('mix.percussion'),
      });
      expect(registry.referencesOf(addr('voice.tom')), {
        addr('mix.percussion'),
      });
      expect(registry.referrersOf(addr('mix.perc')), isEmpty);
      expect(registry.referrersOf(addr('mix.percussion')), {
        addr('voice.bells'),
        addr('voice.tom'),
      });
    });

    test('a ReferenceSource referent has its payload rewritten', () {
      registry.createEntity(addr('mix.perc'));
      registry.createEntity(
        addr('voice.bells'),
        payload: _RefBox({addr('mix.perc')}),
      );

      registry.move(addr('mix.perc'), addr('mix.percussion'));

      final payload = registry.entityAt(addr('voice.bells'))!.payload;
      expect(payload, isA<_RefBox>());
      final box = payload! as _RefBox;
      expect(box.references, {addr('mix.percussion')});
      expect(
        box.rewrites,
        1,
      ); // the registry rewrote the payload, not just refs
    });

    test('moving a group rewrites references to and between its members', () {
      // clip.drums.kick references its sibling clip.drums.snare (internal), and
      // voice.beat references clip.drums.kick (external).
      registry.createEntity(addr('clip.drums.snare'));
      registry.createEntity(
        addr('clip.drums.kick'),
        references: {addr('clip.drums.snare')},
      );
      registry.createEntity(
        addr('voice.beat'),
        references: {addr('clip.drums.kick')},
      );

      registry.move(addr('clip.drums'), addr('clip.percussion.drums'));

      // External referent now points at the moved address …
      expect(registry.referencesOf(addr('voice.beat')), {
        addr('clip.percussion.drums.kick'),
      });
      // … and the internal reference followed the sibling too.
      expect(registry.referencesOf(addr('clip.percussion.drums.kick')), {
        addr('clip.percussion.drums.snare'),
      });
      expect(registry.referrersOf(addr('clip.percussion.drums.kick')), {
        addr('voice.beat'),
      });
    });

    test('renaming does not rewrite references from inside the moved subtree '
        'that point outward', () {
      registry.createEntity(addr('mix.master'));
      registry.createEntity(
        addr('clip.solo'),
        references: {addr('mix.master')},
      );
      registry.move(addr('clip.solo'), addr('clip.lead'));
      // The moved entity still references the untouched external target.
      expect(registry.referencesOf(addr('clip.lead')), {addr('mix.master')});
    });

    test('a pure reparent with no references reuses the node object', () {
      final original = registry.createEntity(addr('clip.a'));
      registry.createGroup(addr('clip.drums'));
      registry.move(addr('clip.a'), addr('clip.drums.a'));
      expect(registry.entityAt(addr('clip.drums.a')), same(original));
    });

    test('the refactor round-trips: moving back restores every reference', () {
      registry.createEntity(addr('mix.perc'));
      registry.createEntity(
        addr('voice.bells'),
        references: {addr('mix.perc')},
      );
      registry.move(addr('mix.perc'), addr('mix.percussion'));
      registry.move(addr('mix.percussion'), addr('mix.perc'));
      expect(registry.referencesOf(addr('voice.bells')), {addr('mix.perc')});
      expect(registry.referrersOf(addr('mix.perc')), {addr('voice.bells')});
    });

    test('a same-parent rename keeps the node in its sibling position', () {
      registry.createEntity(addr('mix.a'));
      registry.createEntity(addr('mix.b'));
      registry.createEntity(addr('mix.c'));

      // Rename the middle one — it must stay in the middle, not jump to the end.
      registry.move(addr('mix.b'), addr('mix.beta'));

      expect(registry.childrenOfKind('mix').map((n) => n.name), [
        'a',
        'beta',
        'c',
      ]);
    });

    test('a reparent (different group) appends at the destination', () {
      registry.createEntity(addr('clip.drums.a'));
      registry.createEntity(addr('clip.drums.b'));
      registry.createEntity(addr('clip.x'));

      // Moving into the drums group lands after its existing members.
      registry.move(addr('clip.x'), addr('clip.drums.x'));

      expect(registry.childrenOfGroup(addr('clip.drums')).map((n) => n.name), [
        'a',
        'b',
        'x',
      ]);
    });
  });

  group('delete warnings (impactOfRemoving)', () {
    test('lists external referents of an entity, sorted', () {
      registry.createEntity(addr('mix.perc'));
      registry.createEntity(addr('voice.tom'), references: {addr('mix.perc')});
      registry.createEntity(
        addr('voice.bells'),
        references: {addr('mix.perc')},
      );

      final impact = registry.impactOfRemoving(addr('mix.perc'));
      expect(impact.target, addr('mix.perc'));
      expect(impact.hasReferrers, isTrue);
      expect(impact.isSafe, isFalse);
      expect(impact.referrers, [addr('voice.bells'), addr('voice.tom')]);
    });

    test('is safe when nothing points at the target', () {
      registry.createEntity(addr('mix.perc'));
      final impact = registry.impactOfRemoving(addr('mix.perc'));
      expect(impact.isSafe, isTrue);
      expect(impact.referrers, isEmpty);
    });

    test('a group lists external referents of anything inside it', () {
      registry.createEntity(addr('clip.drums.kick'));
      registry.createEntity(
        addr('voice.beat'),
        references: {addr('clip.drums.kick')},
      );
      final impact = registry.impactOfRemoving(addr('clip.drums'));
      expect(impact.referrers, [addr('voice.beat')]);
    });

    test('excludes referents that live inside the deleted subtree', () {
      // snare points at kick; both are inside clip.drums, so deleting the group
      // strands nothing external.
      registry.createEntity(addr('clip.drums.kick'));
      registry.createEntity(
        addr('clip.drums.snare'),
        references: {addr('clip.drums.kick')},
      );
      final impact = registry.impactOfRemoving(addr('clip.drums'));
      expect(impact.isSafe, isTrue);
    });

    test('a missing target has a safe, empty impact', () {
      final impact = registry.impactOfRemoving(addr('clip.ghost'));
      expect(impact.isSafe, isTrue);
    });
  });
}
