import 'dart:async';

import 'package:flutter/foundation.dart';

import 'back_reference_index.dart';
import 'delete_impact.dart';
import 'entity_address.dart';
import 'reference_source.dart';
import 'registry_entity.dart';
import 'registry_error.dart';
import 'registry_event.dart';
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
/// **References and refactoring (§4).** Entities point at one another by address
/// (`voice.bells` → `mix.perc`); the registry maintains a [BackReferenceIndex]
/// so it always knows who points at whom. That index powers two things:
/// [move]/rename rewrites every referent as one operation ("rename = refactor"),
/// and [impactOfRemoving] lists the referents a delete would strand ("delete
/// warnings"). An entity declares its edges through its payload (when the
/// payload is a [ReferenceSource]) or explicitly at [createEntity].
///
/// **A [ChangeNotifier]**, so surfaces watch it: every structural mutation
/// bumps [version] and notifies. It also emits a fine-grained [events] stream —
/// the create / move / delete signal the engine's `RegistryMirror` seam mirrors
/// into the Python namespace (design §8). Still **no persistence and no engine
/// knowledge**: `ProjectStore` owns the former, and the registry only *emits*
/// events — the engine-side binder does the mirroring.
///
/// Queries ([nodeAt], [entityAt], [groupAt], [contains], [childrenOfKind],
/// [childrenOfGroup], [referrersOf], [referencesOf], [impactOfRemoving]) never
/// throw — a missing target is `null`/empty. Mutations ([createEntity],
/// [createGroup], [move], [remove], [setReferences]) throw a [RegistryException]
/// on a broken invariant and are transactional: a throw leaves the tree
/// unchanged.
class ProjectRegistry extends ChangeNotifier {
  final Map<String, RegistryGroup> _roots = {};
  final BackReferenceIndex _backrefs = BackReferenceIndex();
  final StreamController<RegistryEvent> _events =
      StreamController<RegistryEvent>.broadcast();
  int _version = 0;

  /// Bumps on every notify — a cheap change signal for listeners and painters.
  int get version => _version;

  /// Fine-grained lifecycle events — one per structural mutation ([createEntity]
  /// / [createGroup] → [RegistryEntityCreated], [move] → [RegistryEntityMoved],
  /// [remove] → [RegistryEntityDeleted]). The `RegistryMirror` seam (design §8)
  /// listens here to keep the engine's Python namespace in step. A broadcast
  /// stream: it buffers nothing, so an event fired before anyone listens is
  /// simply dropped, and [setReferences] emits none (edges are not namespace).
  Stream<RegistryEvent> get events => _events.stream;

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

  /// The entities that reference [target] — the input to a delete warning and
  /// the set a rename rewrites. Empty when nothing points at it. A defensive
  /// copy, safe to iterate while mutating.
  Set<EntityAddress> referrersOf(EntityAddress target) =>
      _backrefs.referrersOf(target);

  /// The addresses the node at [source] points at, or an empty set when
  /// [source] is absent or references nothing. Covers both entities and
  /// payload-carrying group buses (issue #165).
  Set<EntityAddress> referencesOf(EntityAddress source) {
    final node = nodeAt(source);
    if (node is RegistryEntity) return node.references;
    if (node is RegistryGroup) return node.references;
    return const <EntityAddress>{};
  }

  /// What removing the node at [address] would strand: the external entities
  /// left pointing at it (or, for a group, at anything inside it). The delete
  /// warning of design §4 — consult it before calling [remove]. A missing
  /// target yields a safe (empty) impact.
  DeleteImpact impactOfRemoving(EntityAddress address) {
    final node = nodeAt(address);
    final referrers = <EntityAddress>{};
    if (node != null) {
      for (final target in _subtreeAddresses(node, address)) {
        for (final referrer in _backrefs.referrersOf(target)) {
          if (referrer == address || referrer.isDescendantOf(address)) continue;
          referrers.add(referrer);
        }
      }
    }
    final sorted = referrers.toList()
      ..sort((a, b) => a.format().compareTo(b.format()));
    return DeleteImpact(address, sorted);
  }

  /// Creates and returns a new entity at [address], carrying [payload] and
  /// declaring [references] (the addresses it points at).
  ///
  /// When [payload] is a [ReferenceSource] its own references win and
  /// [references] is ignored; otherwise the explicit set is used. The entity's
  /// edges enter the back-reference index immediately.
  ///
  /// Any missing ancestor groups on the path are created first (`mkdir -p`).
  /// Throws a [RegistryException] if an ancestor exists as an entity
  /// ([RegistryError.groupEntityClash]) or the target name is already taken by
  /// a group ([RegistryError.groupEntityClash]) or entity
  /// ([RegistryError.duplicateName]). Notifies on success.
  RegistryEntity createEntity(
    EntityAddress address, {
    Object? payload,
    Set<EntityAddress> references = const {},
  }) {
    final parent = _ensureGroupPath(address.kind, address.groupPath);
    final existing = parent.child(address.name);
    if (existing != null) {
      throw _clashFor(existing, address, creatingGroup: false);
    }
    final entity = RegistryEntity(
      name: address.name,
      kind: address.kind,
      payload: payload,
      references: references,
    );
    parent.put(entity);
    if (entity.references.isNotEmpty) {
      _backrefs.add(address, entity.references);
    }
    _bumpAndNotify();
    _emit(RegistryEntityCreated(address));
    return entity;
  }

  /// Creates the group at [address], plus any missing ancestor groups, and
  /// returns it — optionally carrying an entity [payload] and the [references]
  /// it declares (a group bus's fader/sends, design `docs/design/mix.md` §3).
  ///
  /// Idempotent: if a group already exists at [address] and no [payload] or
  /// [references] are supplied, it is returned unchanged (nothing notifies) —
  /// the `mkdir -p` behaviour ancestor creation relies on. Supplying a payload
  /// for an already-existing group (e.g. one an entity create auto-materialised
  /// as a bare ancestor) *establishes* that payload on it, reindexing its edges
  /// and notifying, but emits no create event since the group already existed.
  ///
  /// When [payload] is a [ReferenceSource] its own references win and
  /// [references] is ignored; otherwise the explicit set is used. Throws a
  /// [RegistryException] ([RegistryError.groupEntityClash]) if an entity already
  /// occupies [address] or any ancestor on the path.
  RegistryGroup createGroup(
    EntityAddress address, {
    Object? payload,
    Set<EntityAddress> references = const {},
  }) {
    final parent = _ensureGroupPath(address.kind, address.groupPath);
    final existing = parent.child(address.name);
    if (existing is RegistryEntity) {
      throw _clashFor(existing, address, creatingGroup: true);
    }
    if (existing is RegistryGroup) {
      if (payload == null && references.isEmpty) return existing;
      _backrefs.removeSource(address);
      existing.assign(payload, references: references);
      if (existing.references.isNotEmpty) {
        _backrefs.add(address, existing.references);
      }
      _bumpAndNotify();
      return existing;
    }
    final group = RegistryGroup(
      address.name,
      payload: payload,
      references: references,
    );
    parent.put(group);
    if (group.references.isNotEmpty) {
      _backrefs.add(address, group.references);
    }
    _bumpAndNotify();
    _emit(RegistryEntityCreated(address));
    return group;
  }

  /// Replaces the outgoing [references] of the entity at [address] and updates
  /// the back-reference index — the hook a future edit command uses so the
  /// index stays current when an entity is re-routed in place.
  ///
  /// When the entity's payload is a [ReferenceSource] its references are
  /// authoritative and [references] is ignored (edit the payload instead).
  /// Throws [RegistryError.notFound] when no entity sits at [address]. Notifies.
  void setReferences(EntityAddress address, Set<EntityAddress> references) {
    final parent = _resolveGroup(address.kind, address.groupPath);
    final existing = parent?.child(address.name);
    if (existing is! RegistryEntity) {
      throw RegistryException(
        RegistryError.notFound,
        'Cannot set references on "$address": no entity is there.',
      );
    }
    parent!.put(
      RegistryEntity(
        name: existing.name,
        kind: existing.kind,
        payload: existing.payload,
        references: references,
      ),
    );
    _backrefs.removeSource(address);
    final resolved = entityAt(address)!.references;
    if (resolved.isNotEmpty) _backrefs.add(address, resolved);
    _bumpAndNotify();
  }

  /// Replaces the [payload] of the entity at [address] in place, keeping its
  /// name, kind and position — the hook a clip edit uses to publish its updated
  /// interpretation into the registry (issue #135, the clip-edit dirty-tracking
  /// seam #123 deferred).
  ///
  /// References follow the new payload when it is a [ReferenceSource] (else the
  /// entity's existing declared references are kept), and the back-reference
  /// index is updated to match. Throws [RegistryError.notFound] when no entity
  /// sits at [address]. Notifies, but emits **no** lifecycle event — a payload
  /// change is not a structural (namespace) mutation, mirroring [setReferences].
  void updateEntityPayload(EntityAddress address, Object? payload) {
    final parent = _resolveGroup(address.kind, address.groupPath);
    final existing = parent?.child(address.name);
    if (existing is! RegistryEntity) {
      throw RegistryException(
        RegistryError.notFound,
        'Cannot update the payload of "$address": no entity is there.',
      );
    }
    parent!.put(
      RegistryEntity(
        name: existing.name,
        kind: existing.kind,
        payload: payload,
        references: existing.references,
      ),
    );
    _backrefs.removeSource(address);
    final resolved = entityAt(address)!.references;
    if (resolved.isNotEmpty) _backrefs.add(address, resolved);
    _bumpAndNotify();
  }

  /// Replaces the [payload] of the *group* at [address] in place, keeping its
  /// name, position and children — the group-bus counterpart of
  /// [updateEntityPayload] (issue #165). This is the hook a group-payload edit
  /// (a group bus's fader/mute/solo) publishes through the command layer so the
  /// change is dirty-tracked and journaled like any other.
  ///
  /// References follow the new payload when it is a [ReferenceSource]; otherwise
  /// the group's existing declared references are kept (a plain-map payload edit
  /// does not by itself re-route sends). The back-reference index is updated to
  /// match. Throws [RegistryError.notFound] when no group sits at [address].
  /// Notifies, but emits **no** lifecycle event — a payload change is not a
  /// structural (namespace) mutation, mirroring [updateEntityPayload].
  void updateGroupPayload(EntityAddress address, Object? payload) {
    final parent = _resolveGroup(address.kind, address.groupPath);
    final existing = parent?.child(address.name);
    if (existing is! RegistryGroup) {
      throw RegistryException(
        RegistryError.notFound,
        'Cannot update the payload of "$address": no group is there.',
      );
    }
    _backrefs.removeSource(address);
    final references = payload is ReferenceSource
        ? payload.references.toSet()
        : existing.references;
    existing.assign(payload, references: references);
    if (existing.references.isNotEmpty) {
      _backrefs.add(address, existing.references);
    }
    _bumpAndNotify();
  }

  /// Reorders [childName] to sit at [index] among the children of the group at
  /// [group] (or the [kind] root when [group] is null) — the `_group.json`
  /// order a Mix-surface section reorder writes (design `docs/design/mix.md`
  /// §7). [index] is the child's final position; [RegistryGroup.reorder] clamps
  /// it into range.
  ///
  /// A reorder shifts no address and rewires no reference, so — like
  /// [setReferences] — it emits **no** lifecycle event; it only [notifyListeners]
  /// so surfaces re-render. A no-op (no notify) when the parent group is absent
  /// or holds no such child.
  void reorderChild({
    required String kind,
    EntityAddress? group,
    required String childName,
    required int index,
  }) {
    final parent = group == null ? _roots[kind] : groupAt(group);
    if (parent == null || !parent.hasChild(childName)) return;
    parent.reorder(childName, index);
    _bumpAndNotify();
  }

  /// Removes the node at [address] — for a group, its whole subtree — and
  /// returns whether anything was removed. Tolerant: a missing target is a
  /// no-op that returns `false` and does not notify.
  ///
  /// Removes the subtree's *outgoing* edges from the index; entities that
  /// pointed *at* the removed node keep their (now dangling) reference — which
  /// is exactly what [impactOfRemoving] warned about. Notifies on success.
  bool remove(EntityAddress address) {
    final parent = _resolveGroup(address.kind, address.groupPath);
    if (parent == null) return false;
    final removed = parent.remove(address.name);
    if (removed == null) return false;
    _deindexSubtree(removed, address);
    _bumpAndNotify();
    _emit(RegistryEntityDeleted(address));
    return true;
  }

  /// Moves the node at [from] to [to] — reparenting it, and renaming it when
  /// `to.name` differs from `from.name` — and **rewrites every referent** so the
  /// project's references follow the address (design §4: rename = refactor). A
  /// group carries its whole subtree, so a move that shifts many addresses at
  /// once rewrites references to *and* between the moved entities. Returns the
  /// addresses of the external entities whose references were rewritten (their
  /// files are now dirty); empty for a no-op move.
  ///
  /// Missing ancestor groups at the destination are created. Throws a
  /// [RegistryException] when: the kinds differ
  /// ([RegistryError.crossKindMove]); nothing exists at [from]
  /// ([RegistryError.notFound]); [to] lands inside the moved group's own
  /// subtree ([RegistryError.moveIntoDescendant]); or the destination name is
  /// taken ([RegistryError.duplicateName] / [RegistryError.groupEntityClash]).
  /// Moving a node onto its own address is a no-op. Notifies on success.
  Set<EntityAddress> move(EntityAddress from, EntityAddress to) {
    if (from.kind != to.kind) {
      throw RegistryException(
        RegistryError.crossKindMove,
        'Cannot move "$from" to "$to": entities never cross namespaces '
        '("${from.kind}" → "${to.kind}").',
      );
    }
    if (from == to) return const {};

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

    // Every address this move changes: the node itself plus every descendant.
    final remap = _buildRemap(node, from, to);

    // Refactor referents that live *outside* the moved subtree, rewriting each
    // in place before the tree changes (their own addresses do not move). A
    // referent may be an entity or a payload-carrying group bus (issue #165).
    final external = _externalReferrers(remap, from);
    for (final referrer in external) {
      final node = nodeAt(referrer);
      if (node is RegistryEntity) {
        final rewritten = _rewriteReferences(node, remap);
        if (!identical(rewritten, node)) {
          _resolveGroup(referrer.kind, referrer.groupPath)!.put(rewritten);
        }
      } else if (node is RegistryGroup) {
        _rewriteGroupReferencesInPlace(node, remap);
      }
    }

    // Rewrite the subtree's internal references, then reattach — renaming the
    // root when its leaf name changed.
    final fromParent = _resolveGroup(from.kind, from.groupPath)!;
    final relocated = _relocate(node, remap);
    final toParent = _ensureGroupPath(to.kind, to.groupPath);
    final reattached = to.name == from.name
        ? relocated
        : _renamedNode(relocated, to.name);
    if (identical(fromParent, toParent)) {
      // A same-parent rename: replace in place so the node keeps its position
      // in the listing rather than jumping to the end (design: a rename must
      // not reorder siblings — the mix rack renames a strip without shuffling
      // it away from its neighbours).
      fromParent.replaceChild(from.name, reattached);
    } else {
      fromParent.remove(from.name);
      toParent.put(reattached);
    }

    // Addresses shifted throughout the subtree, so rebuild the index from the
    // tree rather than trying to patch every moved key incrementally.
    _reindex();
    _bumpAndNotify();
    _emit(RegistryEntityMoved(from, to));
    return external;
  }

  // --- reference / index helpers ------------------------------------------

  /// The external entities (outside the [from] subtree) that reference any
  /// remapped address, read from the pre-move index.
  Set<EntityAddress> _externalReferrers(
    Map<EntityAddress, EntityAddress> remap,
    EntityAddress from,
  ) {
    final external = <EntityAddress>{};
    for (final old in remap.keys) {
      for (final referrer in _backrefs.referrersOf(old)) {
        if (referrer == from || referrer.isDescendantOf(from)) continue;
        external.add(referrer);
      }
    }
    return external;
  }

  /// old → new address for the node at [from] moving to [to] and every
  /// descendant, so both references *to* the subtree and *between* its members
  /// can be repointed.
  Map<EntityAddress, EntityAddress> _buildRemap(
    RegistryNode node,
    EntityAddress from,
    EntityAddress to,
  ) {
    final remap = <EntityAddress, EntityAddress>{from: to};
    if (node is RegistryGroup) _mapChildren(node, from, to, remap);
    return remap;
  }

  void _mapChildren(
    RegistryGroup group,
    EntityAddress fromBase,
    EntityAddress toBase,
    Map<EntityAddress, EntityAddress> remap,
  ) {
    for (final child in group.children) {
      final childFrom = fromBase.child(child.name);
      final childTo = toBase.child(child.name);
      remap[childFrom] = childTo;
      if (child is RegistryGroup) {
        _mapChildren(child, childFrom, childTo, remap);
      }
    }
  }

  /// Rewrites the internal references of every entity in [node]'s subtree,
  /// reusing nodes untouched by [remap]. Returns [node] itself when nothing in
  /// the subtree references a remapped address.
  RegistryNode _relocate(
    RegistryNode node,
    Map<EntityAddress, EntityAddress> remap,
  ) {
    if (node is RegistryEntity) return _rewriteReferences(node, remap);
    final group = node as RegistryGroup;
    // A group bus in the moved subtree may itself reference a remapped address
    // (its sends), so rewrite its own edges before descending (issue #165).
    _rewriteGroupReferencesInPlace(group, remap);
    for (final child in group.children.toList()) {
      final relocated = _relocate(child, remap);
      if (!identical(relocated, child)) group.put(relocated);
    }
    return group;
  }

  /// A copy of [entity] with every reference the [remap] covers repointed —
  /// rewriting the payload too when it is a [ReferenceSource]. Returns the same
  /// instance when no reference is affected, so identity is preserved on a plain
  /// reparent.
  RegistryEntity _rewriteReferences(
    RegistryEntity entity,
    Map<EntityAddress, EntityAddress> remap,
  ) {
    final hits = entity.references.where(remap.containsKey).toList();
    if (hits.isEmpty) return entity;
    var payload = entity.payload;
    if (payload is ReferenceSource) {
      var rewritten = payload;
      for (final old in hits) {
        rewritten = rewritten.withReferenceUpdated(old, remap[old]!);
      }
      payload = rewritten;
    }
    return RegistryEntity(
      name: entity.name,
      kind: entity.kind,
      payload: payload,
      references: entity.references.map((r) => remap[r] ?? r).toSet(),
    );
  }

  /// Rewrites a payload-carrying group's own references in place, keeping its
  /// children — the group counterpart of [_rewriteReferences] (issue #165). A
  /// [ReferenceSource] payload is repointed through [ReferenceSource.withReferenceUpdated];
  /// a plain payload keeps its value and only the declared reference set is
  /// remapped. A no-op when nothing in the group's edges is affected.
  void _rewriteGroupReferencesInPlace(
    RegistryGroup group,
    Map<EntityAddress, EntityAddress> remap,
  ) {
    final hits = group.references.where(remap.containsKey).toList();
    if (hits.isEmpty) return;
    final payload = group.payload;
    if (payload is ReferenceSource) {
      var rewritten = payload;
      for (final old in hits) {
        rewritten = rewritten.withReferenceUpdated(old, remap[old]!);
      }
      group.assign(rewritten);
    } else {
      group.assign(
        payload,
        references: group.references.map((r) => remap[r] ?? r).toSet(),
      );
    }
  }

  RegistryNode _renamedNode(RegistryNode node, String newName) {
    if (node is RegistryEntity) {
      return RegistryEntity(
        name: newName,
        kind: node.kind,
        payload: node.payload,
        references: node.references,
      );
    }
    final group = node as RegistryGroup;
    return RegistryGroup(
      newName,
      payload: group.payload,
      references: group.references,
    )..adoptChildrenFrom(group);
  }

  void _deindexSubtree(RegistryNode node, EntityAddress address) {
    if (node is RegistryEntity) {
      _backrefs.removeSource(address);
    } else if (node is RegistryGroup) {
      // Drop the group bus's own outgoing edges too (issue #165), then recurse.
      _backrefs.removeSource(address);
      for (final child in node.children) {
        _deindexSubtree(child, address.child(child.name));
      }
    }
  }

  Set<EntityAddress> _subtreeAddresses(RegistryNode node, EntityAddress at) {
    final result = <EntityAddress>{at};
    if (node is RegistryGroup) {
      for (final child in node.children) {
        result.addAll(_subtreeAddresses(child, at.child(child.name)));
      }
    }
    return result;
  }

  void _reindex() {
    _backrefs.clear();
    for (final entry in _roots.entries) {
      _indexGroup(entry.key, entry.value, const []);
    }
  }

  void _indexGroup(String kind, RegistryGroup group, List<String> prefix) {
    // Index this group bus's own edges (issue #165). Skipped for the kind root,
    // which has no address (an empty prefix) and never carries a payload.
    if (prefix.isNotEmpty && group.references.isNotEmpty) {
      _backrefs.add(
        EntityAddress(kind: kind, segments: prefix),
        group.references,
      );
    }
    for (final child in group.children) {
      final segments = [...prefix, child.name];
      if (child is RegistryEntity) {
        if (child.references.isNotEmpty) {
          _backrefs.add(
            EntityAddress(kind: kind, segments: segments),
            child.references,
          );
        }
      } else if (child is RegistryGroup) {
        _indexGroup(kind, child, segments);
      }
    }
  }

  // --- tree helpers --------------------------------------------------------

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

  void _emit(RegistryEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// Closes the [events] stream alongside the usual [ChangeNotifier] teardown.
  @override
  void dispose() {
    _events.close();
    super.dispose();
  }
}
