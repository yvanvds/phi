import 'dart:convert';

import '../entity_address.dart';
import '../project_registry.dart';
import '../registry_entity.dart';
import '../registry_group.dart';
import '../registry_node.dart';
import 'entity_payload_codec.dart';
import 'group_metadata.dart';
import 'json_passthrough_codec.dart';
import 'project_manifest.dart';
import 'project_snapshot.dart';
import 'save_plan.dart';

/// The pure heart of the persistence seam: it maps a [ProjectSnapshot] to a flat
/// set of relative-path → contents files and back, with no filesystem in sight.
/// `RealProjectStore` and `FakeProjectStore` both delegate here so the on-disk
/// format lives in exactly one place (design `docs/design/project-registry.md`
/// §5).
///
/// Layout produced:
/// ```
/// project.json                 the manifest
/// <kind>/<group…>/<name>.json  one file per entity; path mirrors the address
/// <kind>/<group…>/_group.json  optional per-group order + colour
/// assets/                      reserved for binaries (ensured, not populated)
/// ```
/// Files are pretty-printed with a trailing newline so they diff cleanly.
///
/// Payloads are (de)serialised through a per-kind [EntityPayloadCodec] (keyed by
/// [codecs]); kinds without a registered codec fall back to
/// [JsonPassthroughCodec], which round-trips `null` and already-JSON payloads.
///
/// **Kind-declared group payloads (issue #165).** A kind in [groupPayloadKinds]
/// declares that its *groups* carry an entity payload too (a `mix.` group is a
/// bus); for such a kind, a group's `_group.json` holds the payload — encoded by
/// the same per-kind [EntityPayloadCodec] — alongside the ordering/colour
/// metadata. Kinds absent from that set are byte-for-byte unchanged: a `clip.`
/// group's `_group.json` still carries order/colour only.
class ProjectSerializer {
  /// Builds a serializer. [codecs] maps a kind to the codec that (de)serialises
  /// its entities' (and group buses') payloads; any kind absent uses
  /// [JsonPassthroughCodec]. [groupPayloadKinds] names the kinds whose groups
  /// carry a persisted payload in `_group.json` (issue #165).
  const ProjectSerializer({
    this.codecs = const {},
    this.groupPayloadKinds = const {},
  });

  /// Per-kind payload codecs. A kind absent here uses the pass-through codec.
  final Map<String, EntityPayloadCodec> codecs;

  /// The kinds whose groups carry a persisted payload in `_group.json`. A kind
  /// absent here has plain structural groups (order/colour metadata only).
  final Set<String> groupPayloadKinds;

  /// The manifest's relative path.
  static const String manifestPath = 'project.json';

  /// The folder reserved for binary assets, ensured on every save.
  static const String assetsDir = 'assets';

  /// The per-group metadata file name.
  static const String groupFileName = '_group.json';

  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');
  static const JsonPassthroughCodec _passthrough = JsonPassthroughCodec();

  EntityPayloadCodec _codecFor(String kind) => codecs[kind] ?? _passthrough;

  /// The relative file path for the entity at [address] —
  /// `kind/group…/name.json`.
  static String entityPath(EntityAddress address) =>
      '${address.kind}/${address.segments.join('/')}.json';

  /// The relative directory for the group at [address] — `kind/group…/name`.
  static String groupDir(EntityAddress address) =>
      '${address.kind}/${address.segments.join('/')}';

  /// The relative `_group.json` path for the group at [address].
  static String groupFile(EntityAddress address) =>
      '${groupDir(address)}/$groupFileName';

  /// Plans a save of [snapshot]. [existingFiles] is the set of relative JSON
  /// paths already on disk (so removals and stale files can be pruned); pass an
  /// empty set for a first save. See [ProjectStore.save] for the dirty vs full
  /// semantics.
  SavePlan planSave(
    ProjectSnapshot snapshot, {
    Set<EntityAddress>? dirty,
    Set<String> existingFiles = const {},
  }) {
    final registry = snapshot.registry;
    final writes = <String, String>{};

    // The manifest is always rewritten — tiny, and holds project-wide state.
    writes[manifestPath] = _write(snapshot.manifest.toJson());

    // Which entities to (re)write: all of them on a full save, else the dirty
    // addresses. A dirty entity writes itself; a dirty *group* (a created group,
    // or a move's destination) writes its whole subtree, so relocated children
    // land at their new addresses.
    final toWrite = <EntityAddress, RegistryEntity>{};
    if (dirty == null) {
      toWrite.addAll(_allEntities(registry));
    } else {
      for (final address in dirty) {
        final entity = registry.entityAt(address);
        if (entity != null) {
          toWrite[address] = entity;
        } else if (registry.groupAt(address) != null) {
          toWrite.addAll(_entitiesUnder(registry, address));
        }
      }
    }
    for (final entry in toWrite.entries) {
      writes[entityPath(entry.key)] = _write(
        _entityJson(entry.key, entry.value),
      );
    }

    // Group files: cosmetic order/colour metadata plus, for a declared kind, the
    // group bus's payload (issue #165). Rewrite every group that has either —
    // these files are tiny, so we don't bother filtering by the dirty set (a
    // dirtied group payload is thus always re-persisted). A group with neither
    // writes no file.
    for (final address in _allGroups(registry)) {
      final json = _groupJson(address, registry.groupAt(address)!, snapshot);
      if (json.isEmpty) continue;
      writes[groupFile(address)] = _write(json);
    }

    final deletes = _plannedDeletes(
      registry: registry,
      dirty: dirty,
      writes: writes,
      existingFiles: existingFiles,
    );

    return SavePlan(
      writes: writes,
      deletes: deletes,
      ensureDirs: const {assetsDir},
    );
  }

  Set<String> _plannedDeletes({
    required ProjectRegistry registry,
    required Set<EntityAddress>? dirty,
    required Map<String, String> writes,
    required Set<String> existingFiles,
  }) {
    final deletes = <String>{};
    if (dirty == null) {
      // Full save mirrors the registry: prune every managed JSON file we did
      // not just write. `assets/` is out of bounds — those are binaries.
      for (final file in existingFiles) {
        if (file == manifestPath) continue;
        if (_underAssets(file)) continue;
        if (!writes.containsKey(file)) deletes.add(file);
      }
      return deletes;
    }
    // Dirty save: delete files for addresses that are no longer present. An
    // absent address that used to be a group takes its whole subtree with it.
    for (final address in dirty) {
      if (registry.entityAt(address) != null) continue;
      if (registry.groupAt(address) != null) continue;
      final file = entityPath(address);
      if (existingFiles.contains(file)) deletes.add(file);
      final prefix = '${groupDir(address)}/';
      for (final existing in existingFiles) {
        if (existing.startsWith(prefix)) deletes.add(existing);
      }
    }
    return deletes;
  }

  /// Rebuilds a [ProjectSnapshot] from the flat [files] map (relative path →
  /// contents), the inverse of [planSave]'s writes.
  ///
  /// Throws a [FormatException] when the manifest is missing. Entities and groups
  /// are created in each group's display order (`_group.json` `order`, else
  /// alphabetical), so the reloaded registry preserves ordering.
  ProjectSnapshot readSnapshot(Map<String, String> files) {
    final manifestRaw = files[manifestPath];
    if (manifestRaw == null) {
      throw const FormatException(
        'Not a project folder: "$manifestPath" is missing.',
      );
    }
    final manifest = ProjectManifest.fromJson(_read(manifestRaw));

    final forest = <String, _DirNode>{};
    _DirNode kindRoot(String kind) =>
        forest.putIfAbsent(kind, () => _DirNode());

    files.forEach((path, contents) {
      if (path == manifestPath || _underAssets(path)) return;
      if (!path.endsWith('.json')) return;
      final parts = path.split('/');
      if (parts.last == groupFileName) {
        // kind/group…/_group.json — metadata for the enclosing group, plus the
        // group bus's payload envelope for a declared kind (issue #165).
        // Kind-root metadata (kind/_group.json) is not modelled, so skip it.
        final groupSegments = parts.sublist(1, parts.length - 1);
        if (groupSegments.isEmpty) return;
        final kind = parts.first;
        final map = _read(contents);
        final node = _descend(kindRoot(kind), groupSegments);
        node.meta = GroupMetadata.fromJson(map);
        if (groupPayloadKinds.contains(kind) &&
            (map.containsKey('payload') || map.containsKey('references'))) {
          node.payloadFile = _groupPayloadFromJson(map);
        }
      } else {
        // kind/group…/name.json — one entity.
        final kind = parts.first;
        final segments = [
          ...parts.sublist(1, parts.length - 1),
          _stem(parts.last),
        ];
        final address = EntityAddress(kind: kind, segments: segments);
        _descend(
          kindRoot(kind),
          segments.sublist(0, segments.length - 1),
        ).entities[address.name] = _entityFromJson(
          _read(contents),
        );
      }
    });

    final registry = ProjectRegistry();
    final groupMetadata = <EntityAddress, GroupMetadata>{};
    for (final kind in forest.keys.toList()..sort()) {
      _emit(registry, groupMetadata, kind, const [], forest[kind]!);
    }

    return ProjectSnapshot(
      manifest: manifest,
      registry: registry,
      groupMetadata: groupMetadata,
    );
  }

  // --- save helpers --------------------------------------------------------

  Map<String, Object?> _entityJson(
    EntityAddress address,
    RegistryEntity entity,
  ) {
    final codec = _codecFor(address.kind);
    final json = <String, Object?>{
      'kind': entity.kind,
      'version': codec.version,
      'name': entity.name,
    };
    if (entity.references.isNotEmpty) {
      final refs = entity.references.map((r) => r.format()).toList()..sort();
      json['references'] = refs;
    }
    final payload = entity.payload == null
        ? null
        : codec.encode(entity.payload);
    if (payload != null) json['payload'] = payload;
    return json;
  }

  /// The `_group.json` map for the group at [address]: its cosmetic order/colour
  /// metadata and — for a declared kind carrying a payload (issue #165) — the
  /// group bus's `kind`/`version`/`name`/`references`/`payload` envelope, encoded
  /// through the kind's [EntityPayloadCodec]. An undeclared kind (or a payload-
  /// free group) yields metadata only, so a `clip.` group is unchanged. Returns
  /// an empty map when there is nothing worth a file.
  Map<String, Object?> _groupJson(
    EntityAddress address,
    RegistryGroup group,
    ProjectSnapshot snapshot,
  ) {
    final meta = snapshot.groupMetadata[address] ?? const GroupMetadata();
    final json = <String, Object?>{...meta.toJson()};
    if (!groupPayloadKinds.contains(address.kind)) return json;
    if (group.payload == null && group.references.isEmpty) return json;
    final codec = _codecFor(address.kind);
    json['kind'] = address.kind;
    json['version'] = codec.version;
    json['name'] = group.name;
    if (group.references.isNotEmpty) {
      final refs = group.references.map((r) => r.format()).toList()..sort();
      json['references'] = refs;
    }
    final payload = group.payload == null ? null : codec.encode(group.payload);
    if (payload != null) json['payload'] = payload;
    return json;
  }

  Map<EntityAddress, RegistryEntity> _allEntities(ProjectRegistry registry) {
    final result = <EntityAddress, RegistryEntity>{};
    void walk(String kind, List<String> prefix, Iterable<RegistryNode> nodes) {
      for (final node in nodes) {
        final segments = [...prefix, node.name];
        final address = EntityAddress(kind: kind, segments: segments);
        if (node is RegistryEntity) {
          result[address] = node;
        } else if (node is RegistryGroup) {
          walk(kind, segments, registry.childrenOfGroup(address));
        }
      }
    }

    for (final kind in registry.kinds) {
      walk(kind, const [], registry.childrenOfKind(kind));
    }
    return result;
  }

  /// Every entity in the subtree rooted at the group [group], keyed by address —
  /// what a dirty save rewrites when a whole group is created or relocated.
  Map<EntityAddress, RegistryEntity> _entitiesUnder(
    ProjectRegistry registry,
    EntityAddress group,
  ) {
    final result = <EntityAddress, RegistryEntity>{};
    void walk(EntityAddress at) {
      for (final node in registry.childrenOfGroup(at)) {
        final childAddress = at.child(node.name);
        if (node is RegistryEntity) {
          result[childAddress] = node;
        } else if (node is RegistryGroup) {
          walk(childAddress);
        }
      }
    }

    walk(group);
    return result;
  }

  /// Every group address in the tree (kind roots excluded — they are not
  /// addressable), in a stable pre-order — the set whose `_group.json` files a
  /// save considers writing.
  List<EntityAddress> _allGroups(ProjectRegistry registry) {
    final result = <EntityAddress>[];
    void walk(String kind, List<String> prefix, Iterable<RegistryNode> nodes) {
      for (final node in nodes) {
        if (node is! RegistryGroup) continue;
        final segments = [...prefix, node.name];
        final address = EntityAddress(kind: kind, segments: segments);
        result.add(address);
        walk(kind, segments, registry.childrenOfGroup(address));
      }
    }

    for (final kind in registry.kinds) {
      walk(kind, const [], registry.childrenOfKind(kind));
    }
    return result;
  }

  // --- load helpers --------------------------------------------------------

  _DirNode _descend(_DirNode from, List<String> segments) {
    var current = from;
    for (final segment in segments) {
      current = current.groups.putIfAbsent(segment, () => _DirNode());
    }
    return current;
  }

  void _emit(
    ProjectRegistry registry,
    Map<EntityAddress, GroupMetadata> groupMetadata,
    String kind,
    List<String> prefix,
    _DirNode node,
  ) {
    final names = <String>{...node.groups.keys, ...node.entities.keys};
    for (final name in _ordered(names, node.meta?.order)) {
      final segments = [...prefix, name];
      final address = EntityAddress(kind: kind, segments: segments);
      final entity = node.entities[name];
      if (entity != null) {
        final codec = _codecFor(kind);
        registry.createEntity(
          address,
          payload: entity.payloadJson == null
              ? null
              : codec.decode(entity.payloadJson, entity.version),
          references: entity.references,
        );
      } else {
        final child = node.groups[name]!;
        final pf = child.payloadFile;
        if (pf != null) {
          // A declared kind's group bus (issue #165): decode its payload through
          // the kind's codec, matching the entity path.
          final codec = _codecFor(kind);
          registry.createGroup(
            address,
            payload: pf.payloadJson == null
                ? null
                : codec.decode(pf.payloadJson, pf.version),
            references: pf.references,
          );
        } else {
          registry.createGroup(address);
        }
        if (child.meta != null && !child.meta!.isEmpty) {
          groupMetadata[address] = child.meta!;
        }
        _emit(registry, groupMetadata, kind, segments, child);
      }
    }
  }

  _EntityFile _entityFromJson(Map<String, Object?> json) {
    return _EntityFile(
      version: json['version'] as int? ?? 1,
      payloadJson: json['payload'],
      references: _referencesFromJson(json),
    );
  }

  _GroupPayloadFile _groupPayloadFromJson(Map<String, Object?> json) {
    return _GroupPayloadFile(
      version: json['version'] as int? ?? 1,
      payloadJson: json['payload'],
      references: _referencesFromJson(json),
    );
  }

  Set<EntityAddress> _referencesFromJson(Map<String, Object?> json) =>
      (json['references'] as List<Object?>?)
          ?.map((e) => EntityAddress.parse(e as String))
          .toSet() ??
      const <EntityAddress>{};

  /// Names in [order] first (those present in [names]), then the rest
  /// alphabetically — the default when a group has no `order`.
  List<String> _ordered(Set<String> names, List<String>? order) {
    if (order == null || order.isEmpty) return names.toList()..sort();
    final result = <String>[
      for (final name in order)
        if (names.contains(name)) name,
    ];
    final placed = result.toSet();
    result.addAll(names.where((n) => !placed.contains(n)).toList()..sort());
    return result;
  }

  String _write(Map<String, Object?> json) => '${_encoder.convert(json)}\n';

  Map<String, Object?> _read(String contents) =>
      jsonDecode(contents) as Map<String, Object?>;

  static bool _underAssets(String path) => path.startsWith('$assetsDir/');

  static String _stem(String fileName) =>
      fileName.substring(0, fileName.length - '.json'.length);
}

/// A group node in the tree the loader rebuilds from flat file paths, before it
/// is replayed into a [ProjectRegistry] in display order.
class _DirNode {
  final Map<String, _DirNode> groups = {};
  final Map<String, _EntityFile> entities = {};
  GroupMetadata? meta;

  /// The group bus's payload envelope, when this group's `_group.json` carried
  /// one for a declared kind (issue #165); `null` for a plain folder.
  _GroupPayloadFile? payloadFile;
}

/// A parsed entity file awaiting creation (payload still JSON until its codec
/// decodes it in creation order).
class _EntityFile {
  _EntityFile({
    required this.version,
    required this.payloadJson,
    required this.references,
  });

  final int version;
  final Object? payloadJson;
  final Set<EntityAddress> references;
}

/// A parsed group-payload envelope from a `_group.json` (issue #165) — the
/// group-bus counterpart of [_EntityFile], its payload still JSON until the
/// kind's codec decodes it in creation order.
class _GroupPayloadFile {
  _GroupPayloadFile({
    required this.version,
    required this.payloadJson,
    required this.references,
  });

  final int version;
  final Object? payloadJson;
  final Set<EntityAddress> references;
}
