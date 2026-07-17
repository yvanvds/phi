import 'package:flutter/foundation.dart';

import 'entity_address.dart';
import 'registry_entity.dart';
import 'registry_error.dart';
import 'registry_exception.dart';
import 'registry_group.dart';
import 'registry_node.dart';

/// The in-memory tree of every group and entity while the app runs — the single
/// source of truth the design (`docs/design/project-registry.md` §2, §8) builds
/// the whole project model on.
///
/// **Kind-generic from day one.** One root [RegistryGroup] per kind (`clip`,
/// `mix`, `voice`, …); kinds spring into existence the first time something is
/// created under them and hold entities of that namespace side by side. The
/// core knows nothing about what a clip or a mix bus *is* — only names,
/// addresses, and tree shape.
///
/// **A [ChangeNotifier]**, so surfaces watch it: every structural mutation
/// bumps [version] and notifies. **No persistence and no engine knowledge** —
/// those seams (`ProjectStore`, `RegistryMirror`) arrive in later epic issues.
///
/// Queries ([nodeAt], [entityAt], [groupAt], [contains], [childrenOfKind],
/// [childrenOfGroup]) never throw — a missing target is `null`/empty. Mutations
/// ([createEntity], [createGroup], [move], [remove]) throw a [RegistryException]
/// on a broken invariant and are transactional: a throw leaves the tree
/// unchanged.
class ProjectRegistry extends ChangeNotifier {
  final Map<String, RegistryGroup> _roots = {};
  int _version = 0;

  /// Bumps on every notify — a cheap change signal for listeners and painters.
  int get version => _version;

  /// The kinds that currently have a root. A namespace persists once created,
  /// even if later emptied.
  Iterable<String> get kinds => _roots.keys;

  /// The node at [address], or `null` if nothing is there (or the path runs
  /// through an entity where a group was expected).
  RegistryNode? nodeAt(EntityAddress address) {
    final parent = _resolveGroup(address.kind, address.groupPath);
    return parent?.child(address.name);
  }

  /// The entity at [address], or `null` if absent or a group sits there.
  RegistryEntity? entityAt(EntityAddress address) {
    final node = nodeAt(address);
    return node is RegistryEntity ? node : null;
  }

  /// The group at [address], or `null` if absent or an entity sits there.
  RegistryGroup? groupAt(EntityAddress address) {
    final node = nodeAt(address);
    return node is RegistryGroup ? node : null;
  }

  /// Whether any node exists at [address].
  bool contains(EntityAddress address) => nodeAt(address) != null;

  /// The top-level children under [kind]'s root, in insertion order. Empty if
  /// the kind has no root yet.
  List<RegistryNode> childrenOfKind(String kind) =>
      _roots[kind]?.children.toList(growable: false) ?? const [];

  /// The direct children of the group at [group], in insertion order. Empty if
  /// [group] is absent or is an entity rather than a group.
  List<RegistryNode> childrenOfGroup(EntityAddress group) =>
      groupAt(group)?.children.toList(growable: false) ?? const [];

  /// Creates and returns a new entity at [address], carrying [payload].
  ///
  /// Any missing ancestor groups on the path are created first (`mkdir -p`).
  /// Throws a [RegistryException] if an ancestor exists as an entity
  /// ([RegistryError.groupEntityClash]) or the target name is already taken by
  /// a group ([RegistryError.groupEntityClash]) or entity
  /// ([RegistryError.duplicateName]). Notifies on success.
  RegistryEntity createEntity(EntityAddress address, {Object? payload}) {
    final parent = _ensureGroupPath(address.kind, address.groupPath);
    final existing = parent.child(address.name);
    if (existing != null) {
      throw _clashFor(existing, address, creatingGroup: false);
    }
    final entity = RegistryEntity(
      name: address.name,
      kind: address.kind,
      payload: payload,
    );
    parent.put(entity);
    _bumpAndNotify();
    return entity;
  }

  /// Creates the group at [address], plus any missing ancestor groups, and
  /// returns it. Idempotent: if a group already exists at [address] it is
  /// returned unchanged (and nothing notifies). Throws a [RegistryException]
  /// ([RegistryError.groupEntityClash]) if an entity already occupies [address]
  /// or any ancestor on the path. Notifies only when a group is actually added.
  RegistryGroup createGroup(EntityAddress address) {
    final parent = _ensureGroupPath(address.kind, address.groupPath);
    final existing = parent.child(address.name);
    if (existing is RegistryGroup) return existing;
    if (existing is RegistryEntity) {
      throw _clashFor(existing, address, creatingGroup: true);
    }
    final group = RegistryGroup(address.name);
    parent.put(group);
    _bumpAndNotify();
    return group;
  }

  /// Removes the node at [address] — for a group, its whole subtree — and
  /// returns whether anything was removed. Tolerant: a missing target is a
  /// no-op that returns `false` and does not notify.
  bool remove(EntityAddress address) {
    final parent = _resolveGroup(address.kind, address.groupPath);
    if (parent == null) return false;
    if (parent.remove(address.name) == null) return false;
    _bumpAndNotify();
    return true;
  }

  /// Moves the node at [from] to [to] — reparenting it, and renaming it when
  /// `to.name` differs from `from.name`. A group carries its whole subtree.
  ///
  /// Missing ancestor groups at the destination are created. Throws a
  /// [RegistryException] when: the kinds differ
  /// ([RegistryError.crossKindMove]); nothing exists at [from]
  /// ([RegistryError.notFound]); [to] lands inside the moved group's own
  /// subtree ([RegistryError.moveIntoDescendant]); or the destination name is
  /// taken ([RegistryError.duplicateName] / [RegistryError.groupEntityClash]).
  /// Moving a node onto its own address is a no-op. Notifies on success.
  void move(EntityAddress from, EntityAddress to) {
    if (from.kind != to.kind) {
      throw RegistryException(
        RegistryError.crossKindMove,
        'Cannot move "$from" to "$to": entities never cross namespaces '
        '("${from.kind}" → "${to.kind}").',
      );
    }
    if (from == to) return;

    final node = nodeAt(from);
    if (node == null) {
      throw RegistryException(
        RegistryError.notFound,
        'Cannot move "$from": nothing exists there.',
      );
    }
    if (node is RegistryGroup && to.isDescendantOf(from)) {
      throw RegistryException(
        RegistryError.moveIntoDescendant,
        'Cannot move group "$from" into its own subtree at "$to".',
      );
    }

    // Validate the destination read-only, before detaching anything, so a
    // clash leaves the tree untouched.
    final destParent = _validateDestinationParent(to);
    final destOccupant = destParent?.child(to.name);
    if (destOccupant != null) {
      throw _clashFor(destOccupant, to, creatingGroup: node is RegistryGroup);
    }

    // Detach, then reattach. Reuse the node object on a pure reparent; rebuild
    // it under the new name on a rename (node.name is immutable), reusing the
    // subtree's descendants either way.
    _resolveGroup(from.kind, from.groupPath)!.remove(from.name);
    final parent = _ensureGroupPath(to.kind, to.groupPath);
    parent.put(to.name == from.name ? node : _renamed(node, to.name));
    _bumpAndNotify();
  }

  /// Walks (and creates) the group path [groupSegments] under [kind], returning
  /// the group the leaf should hang from. Throws [RegistryError.groupEntityClash]
  /// if a segment on the path already exists as an entity. Transactional: the
  /// clash is detected while descending the *existing* prefix, before any group
  /// is created, so a throw never leaves half-built groups behind.
  RegistryGroup _ensureGroupPath(String kind, List<String> groupSegments) {
    var current = _roots.putIfAbsent(kind, () => RegistryGroup(kind));
    for (final segment in groupSegments) {
      final existing = current.child(segment);
      if (existing is RegistryGroup) {
        current = existing;
      } else if (existing is RegistryEntity) {
        throw RegistryException(
          RegistryError.groupEntityClash,
          'Cannot use "$segment" as a group under "$kind": an entity already '
          'uses that name.',
        );
      } else {
        final group = RegistryGroup(segment);
        current.put(group);
        current = group;
      }
    }
    return current;
  }

  /// Resolves the group at the path [groupSegments] under [kind] without
  /// creating anything, or `null` if any segment is missing or is an entity.
  /// An empty [groupSegments] resolves to the kind root.
  RegistryGroup? _resolveGroup(String kind, List<String> groupSegments) {
    var current = _roots[kind];
    for (final segment in groupSegments) {
      final child = current?.child(segment);
      if (child is! RegistryGroup) return null;
      current = child;
    }
    return current;
  }

  /// Read-only resolution of the destination *parent* for a move: descends the
  /// group path above [to], returning the parent group, or `null` when it does
  /// not fully exist yet (it will be created, so nothing can clash below).
  /// Throws [RegistryError.groupEntityClash] if the path runs through an entity.
  RegistryGroup? _validateDestinationParent(EntityAddress to) {
    var current = _roots[to.kind];
    for (final segment in to.groupPath) {
      if (current == null) return null;
      final child = current.child(segment);
      if (child is RegistryEntity) {
        throw RegistryException(
          RegistryError.groupEntityClash,
          'Cannot move into "$to": an entity named "$segment" blocks the path.',
        );
      }
      if (child is! RegistryGroup) return null;
      current = child;
    }
    return current;
  }

  RegistryNode _renamed(RegistryNode node, String newName) {
    if (node is RegistryEntity) {
      return RegistryEntity(
        name: newName,
        kind: node.kind,
        payload: node.payload,
      );
    }
    return RegistryGroup(newName)..adoptChildrenFrom(node as RegistryGroup);
  }

  RegistryException _clashFor(
    RegistryNode occupant,
    EntityAddress address, {
    required bool creatingGroup,
  }) {
    final occupantIsGroup = occupant is RegistryGroup;
    final what = creatingGroup ? 'group' : 'entity';
    if (occupantIsGroup == creatingGroup) {
      return RegistryException(
        RegistryError.duplicateName,
        'A $what already exists at "$address".',
      );
    }
    return RegistryException(
      RegistryError.groupEntityClash,
      'Cannot create $what "$address": a '
      '${occupantIsGroup ? 'group' : 'entity'} of that name already exists at '
      'the same level.',
    );
  }

  void _bumpAndNotify() {
    _version++;
    notifyListeners();
  }
}
