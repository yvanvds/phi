import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/reference_source.dart';
import 'package:phi/domain/project/registry_error.dart';
import 'package:phi/domain/project/registry_exception.dart';

EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

Matcher throwsRegistry(RegistryError error) =>
    throwsA(isA<RegistryException>().having((e) => e.error, 'error', error));

/// A payload that references others by address and rewrites them structurally —
/// the stand-in for a real `mix.` group-bus payload (its sends) until #166
/// grows `MixStrip` into a [ReferenceSource]. Counts rewrites so a test can
/// assert the registry rewrote the *payload*, not just the declared set.
class _SendingBus implements ReferenceSource {
  _SendingBus(this.references, {this.rewrites = 0});

  @override
  final Set<EntityAddress> references;

  final int rewrites;

  @override
  ReferenceSource withReferenceUpdated(EntityAddress from, EntityAddress to) =>
      _SendingBus(
        references.map((r) => r == from ? to : r).toSet(),
        rewrites: rewrites + 1,
      );
}

void main() {
  late ProjectRegistry registry;

  setUp(() => registry = ProjectRegistry());

  group('createGroup with a payload', () {
    test('stores the payload on the group', () {
      registry.createGroup(
        addr('mix.drums'),
        payload: const {'name': 'Drums', 'voice': 2, 'volume': 0.8},
      );
      expect(registry.groupAt(addr('mix.drums'))!.payload, const {
        'name': 'Drums',
        'voice': 2,
        'volume': 0.8,
      });
    });

    test('indexes explicit references as the group bus edges', () {
      registry.createEntity(addr('mix.verb'));
      registry.createGroup(
        addr('mix.drums'),
        payload: const {'name': 'Drums'},
        references: {addr('mix.verb')},
      );

      expect(registry.referencesOf(addr('mix.drums')), {addr('mix.verb')});
      expect(registry.referrersOf(addr('mix.verb')), {addr('mix.drums')});
    });

    test('derives references from a ReferenceSource payload', () {
      registry.createEntity(addr('mix.verb'));
      registry.createGroup(
        addr('mix.drums'),
        payload: _SendingBus({addr('mix.verb')}),
      );

      expect(registry.referencesOf(addr('mix.drums')), {addr('mix.verb')});
      expect(registry.referrersOf(addr('mix.verb')), {addr('mix.drums')});
    });

    test('establishes a payload on an auto-created ancestor group', () {
      // The entity create materialises `mix.drums` as a bare structural group.
      registry.createEntity(addr('mix.drums.kick'));
      expect(registry.groupAt(addr('mix.drums'))!.payload, isNull);

      registry.createEntity(addr('mix.verb'));
      registry.createGroup(
        addr('mix.drums'),
        payload: const {'name': 'Drums'},
        references: {addr('mix.verb')},
      );

      expect(registry.groupAt(addr('mix.drums'))!.payload, const {
        'name': 'Drums',
      });
      expect(registry.referrersOf(addr('mix.verb')), {addr('mix.drums')});
      // The child is untouched.
      expect(registry.contains(addr('mix.drums.kick')), isTrue);
    });

    test('a bare create on an existing group leaves it unchanged', () {
      registry.createGroup(addr('mix.drums'), payload: const {'name': 'Drums'});
      registry.createGroup(addr('mix.drums')); // idempotent, no payload
      expect(registry.groupAt(addr('mix.drums'))!.payload, const {
        'name': 'Drums',
      });
    });
  });

  group('updateGroupPayload', () {
    test('replaces the payload in place, keeping children', () {
      registry.createGroup(
        addr('mix.drums'),
        payload: const {'name': 'Drums', 'volume': 1.0},
      );
      registry.createEntity(addr('mix.drums.kick'));

      registry.updateGroupPayload(addr('mix.drums'), const {
        'name': 'Drums',
        'volume': 0.5,
        'muted': true,
      });

      expect(registry.groupAt(addr('mix.drums'))!.payload, const {
        'name': 'Drums',
        'volume': 0.5,
        'muted': true,
      });
      expect(registry.contains(addr('mix.drums.kick')), isTrue);
    });

    test('re-derives references from a ReferenceSource payload', () {
      registry.createEntity(addr('mix.verb'));
      registry.createEntity(addr('mix.echo'));
      registry.createGroup(
        addr('mix.drums'),
        payload: _SendingBus({addr('mix.verb')}),
      );

      registry.updateGroupPayload(
        addr('mix.drums'),
        _SendingBus({addr('mix.echo')}),
      );

      expect(registry.referencesOf(addr('mix.drums')), {addr('mix.echo')});
      expect(registry.referrersOf(addr('mix.verb')), isEmpty);
      expect(registry.referrersOf(addr('mix.echo')), {addr('mix.drums')});
    });

    test('keeps declared references for a plain payload edit', () {
      registry.createEntity(addr('mix.verb'));
      registry.createGroup(
        addr('mix.drums'),
        payload: const {'volume': 1.0},
        references: {addr('mix.verb')},
      );

      registry.updateGroupPayload(addr('mix.drums'), const {'volume': 0.3});

      expect(registry.referrersOf(addr('mix.verb')), {addr('mix.drums')});
    });

    test('throws notFound when no group sits there', () {
      registry.createEntity(addr('mix.strip'));
      expect(
        () => registry.updateGroupPayload(addr('mix.strip'), const {}),
        throwsRegistry(RegistryError.notFound),
      );
      expect(
        () => registry.updateGroupPayload(addr('mix.absent'), const {}),
        throwsRegistry(RegistryError.notFound),
      );
    });
  });

  group('delete-impact covers group-payload references', () {
    test('removing a return warns about the group bus that sends to it', () {
      registry.createEntity(addr('mix.verb'));
      registry.createGroup(
        addr('mix.drums'),
        payload: const {'name': 'Drums'},
        references: {addr('mix.verb')},
      );

      final impact = registry.impactOfRemoving(addr('mix.verb'));
      expect(impact.referrers, [addr('mix.drums')]);
    });

    test('a ReferenceSource group bus also shows up in delete-impact', () {
      registry.createEntity(addr('mix.verb'));
      registry.createGroup(
        addr('mix.drums'),
        payload: _SendingBus({addr('mix.verb')}),
      );

      expect(registry.impactOfRemoving(addr('mix.verb')).referrers, [
        addr('mix.drums'),
      ]);
    });

    test('removing the group bus drops its own outgoing edges', () {
      registry.createEntity(addr('mix.verb'));
      registry.createGroup(addr('mix.drums'), references: {addr('mix.verb')});
      expect(registry.referrersOf(addr('mix.verb')), {addr('mix.drums')});

      registry.remove(addr('mix.drums'));
      expect(registry.referrersOf(addr('mix.verb')), isEmpty);
    });
  });

  group('rename-refactor covers group-payload references', () {
    test('renaming a return rewrites the group bus\'s declared send', () {
      registry.createEntity(addr('mix.verb'));
      registry.createGroup(
        addr('mix.drums'),
        payload: const {'name': 'Drums'},
        references: {addr('mix.verb')},
      );

      final touched = registry.move(addr('mix.verb'), addr('mix.reverb'));

      // The group bus is reported dirty, and its send now points at the new
      // address in both the index and its reference set.
      expect(touched, contains(addr('mix.drums')));
      expect(registry.referencesOf(addr('mix.drums')), {addr('mix.reverb')});
      expect(registry.referrersOf(addr('mix.reverb')), {addr('mix.drums')});
      expect(registry.referrersOf(addr('mix.verb')), isEmpty);
    });

    test('renaming a return rewrites a ReferenceSource group payload', () {
      registry.createEntity(addr('mix.verb'));
      registry.createGroup(
        addr('mix.drums'),
        payload: _SendingBus({addr('mix.verb')}),
      );

      registry.move(addr('mix.verb'), addr('mix.reverb'));

      final payload = registry.groupAt(addr('mix.drums'))!.payload;
      expect(payload, isA<_SendingBus>());
      expect((payload as _SendingBus).references, {addr('mix.reverb')});
      expect(payload.rewrites, 1);
    });

    test('moving a group bus carries its payload and references', () {
      registry.createEntity(addr('mix.verb'));
      registry.createGroup(
        addr('mix.drums'),
        payload: const {'name': 'Drums'},
        references: {addr('mix.verb')},
      );
      registry.createEntity(addr('mix.drums.kick'));

      registry.move(addr('mix.drums'), addr('mix.percussion'));

      expect(registry.groupAt(addr('mix.percussion'))!.payload, const {
        'name': 'Drums',
      });
      expect(registry.referencesOf(addr('mix.percussion')), {addr('mix.verb')});
      expect(registry.referrersOf(addr('mix.verb')), {addr('mix.percussion')});
      expect(registry.contains(addr('mix.percussion.kick')), isTrue);
      expect(registry.contains(addr('mix.drums')), isFalse);
    });
  });
}
