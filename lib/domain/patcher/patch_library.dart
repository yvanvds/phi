import 'dart:convert';

import '../project/commands/create_entity_command.dart';
import '../project/entity_address.dart';
import '../project/name_slug.dart';
import '../project/project_registry.dart';
import '../project/registry_kinds.dart';
import 'patch_payload.dart';

/// The `patch.` library commands (design `docs/design/patcher.md` §3, §8) — the
/// pure-domain half of the patcher entity strip (epic issue #224).
///
/// Every patch is a registry entity carrying a [PatchPayload] (the engine dump +
/// its source placement); the library is the set of operations that *mint* those
/// entities:
///
/// - [newPatch] — an **empty** patch (no objects, unplaced) at a chosen address.
/// - [duplicate] — the whole payload copied verbatim to `<name>_copy` beside the
///   original (dump and placement alike — a byte-for-byte JSON clone).
///
/// Both return an ordinary [CreateEntityCommand] — the journaled command layer,
/// so each round-trips through save/load *and* undo (delete/rename need no new
/// command; the registry already carries them). The caller applies and records
/// the command; the library itself never mutates the registry, keeping it a pure
/// command factory (mirroring `ClipLibrary`).
class PatchLibrary {
  /// Binds the library to [registry] — the source the minted commands target.
  PatchLibrary(this.registry);

  /// The registry the minted commands create entities in.
  final ProjectRegistry registry;

  /// Builds a command that creates an **empty** patch (no objects, unplaced)
  /// under [group] (or top-level when null), named from [name] (slugged, made
  /// unique among its siblings).
  CreateEntityCommand newPatch({EntityAddress? group, String name = 'patch'}) {
    return CreateEntityCommand(
      registry,
      _freshAddress(
        group: group,
        desired: NameSlug.of(name, fallback: 'patch'),
      ),
      payload: PatchPayload.empty.toJson(),
    );
  }

  /// Builds a command that copies the patch at [source] — its whole payload,
  /// dump and placement alike — to `<name>_copy` beside it (made unique).
  ///
  /// The stored payload is copied **verbatim** (a deep JSON clone), so the copy
  /// carries the same graph and the same source placement. Throws an
  /// [ArgumentError] when no patch entity sits at [source].
  CreateEntityCommand duplicate(EntityAddress source) {
    final entity = registry.entityAt(source);
    if (entity == null) {
      throw ArgumentError.value(
        source.format(),
        'source',
        'no patch entity to duplicate',
      );
    }
    return CreateEntityCommand(
      registry,
      _freshAddress(group: source.parent, desired: '${source.name}_copy'),
      payload: _clonePayload(entity.payload),
    );
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  /// A `patch.` address for [desired] under [group] (top-level when null), made
  /// unique among its siblings by suffixing `_2`, `_3`, …
  EntityAddress _freshAddress({
    required EntityAddress? group,
    required String desired,
  }) {
    if (group != null && group.kind != RegistryKinds.patch) {
      throw ArgumentError.value(
        group.format(),
        'group',
        'a patch must live under a "${RegistryKinds.patch}" group',
      );
    }
    EntityAddress at(String leaf) => group == null
        ? EntityAddress(kind: RegistryKinds.patch, segments: [leaf])
        : group.child(leaf);
    var leaf = desired;
    var attempt = 2;
    while (registry.contains(at(leaf))) {
      leaf = NameSlug.of('${desired}_$attempt', fallback: 'patch');
      attempt++;
    }
    return at(leaf);
  }

  /// A deep clone of a stored patch [payload] for a duplicate. The registry keeps
  /// patch payloads map-native (the journal contract), so a JSON round-trip is a
  /// full deep copy; a live [PatchPayload] is flattened through its `toJson`.
  Object _clonePayload(Object? payload) {
    if (payload is PatchPayload) return payload.toJson();
    if (payload is Map) {
      return (jsonDecode(jsonEncode(payload)) as Map).cast<String, Object?>();
    }
    // An empty/absent payload duplicates as an empty patch.
    return PatchPayload.empty.toJson();
  }
}
