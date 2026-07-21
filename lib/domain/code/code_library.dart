import 'dart:convert';

import '../project/commands/create_entity_command.dart';
import '../project/entity_address.dart';
import '../project/name_slug.dart';
import '../project/project_registry.dart';
import '../project/registry_kinds.dart';
import 'code_script.dart';

/// The `code.` library commands (design `docs/design/live-coding.md` §5) — the
/// pure-domain half of the script library (issue #235), mirroring `ClipLibrary`.
///
/// Every script is a registry entity carrying a [CodeScript] payload; the
/// library is the set of operations that *mint* those entities:
///
/// - [newScript] — an empty script at a chosen address.
/// - [duplicate] — the source copied verbatim to `<name>_copy` beside the
///   original.
///
/// Both return an ordinary [CreateEntityCommand] — the journaled command layer,
/// so each round-trips through save/load *and* undo. Rename and delete need no
/// new command; the registry already carries them. The caller applies and
/// records the command (through the surface's `UndoScope` / `ProjectController`);
/// the library itself never mutates the registry, keeping it a pure command
/// factory.
class CodeLibrary {
  /// Binds the library to [registry] — the tree the minted commands target.
  CodeLibrary(this.registry);

  /// The registry the minted commands target.
  final ProjectRegistry registry;

  /// Builds a command that creates an **empty** script under [group] (or
  /// top-level when null), named from [name] (slugged, made unique among its
  /// siblings).
  CreateEntityCommand newScript({
    EntityAddress? group,
    String name = 'script',
  }) {
    return CreateEntityCommand(
      registry,
      _freshAddress(
        group: group,
        desired: NameSlug.of(name, fallback: 'script'),
      ),
      payload: const CodeScript().toJson(),
    );
  }

  /// Builds a command that copies the script at [source] — its source text — to
  /// `<name>_copy` beside it (made unique). Throws an [ArgumentError] when no
  /// script entity sits at [source].
  CreateEntityCommand duplicate(EntityAddress source) {
    final entity = registry.entityAt(source);
    if (entity == null) {
      throw ArgumentError.value(
        source.format(),
        'source',
        'no code entity to duplicate',
      );
    }
    return CreateEntityCommand(
      registry,
      _freshAddress(group: source.parent, desired: '${source.name}_copy'),
      payload: _clonePayload(entity.payload),
    );
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  /// A `code.` address for [desired] under [group] (top-level when null), made
  /// unique among its siblings by suffixing `_2`, `_3`, … — the tree-uniqueness
  /// [NameSlug] deliberately leaves to the caller.
  EntityAddress _freshAddress({
    required EntityAddress? group,
    required String desired,
  }) {
    if (group != null && group.kind != RegistryKinds.code) {
      throw ArgumentError.value(
        group.format(),
        'group',
        'a script must live under a "${RegistryKinds.code}" group',
      );
    }
    EntityAddress at(String leaf) => group == null
        ? EntityAddress(kind: RegistryKinds.code, segments: [leaf])
        : group.child(leaf);
    var leaf = desired;
    var attempt = 2;
    while (registry.contains(at(leaf))) {
      leaf = NameSlug.of('${desired}_$attempt', fallback: 'script');
      attempt++;
    }
    return at(leaf);
  }

  /// A deep clone of a stored script [payload] for a duplicate. The registry
  /// keeps payloads map-native (the journal contract), so a JSON round-trip is a
  /// full deep copy; a live [CodeScript] flattens through its `toJson`.
  Object _clonePayload(Object? payload) {
    if (payload is CodeScript) return payload.toJson();
    if (payload is Map) {
      return (jsonDecode(jsonEncode(payload)) as Map).cast<String, Object?>();
    }
    throw ArgumentError.value(
      payload,
      'payload',
      'code entity has no source payload to duplicate',
    );
  }
}
