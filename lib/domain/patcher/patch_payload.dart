import '../project/entity_address.dart';

/// The payload of a `patch.` registry entity — the engine's `dumpJson`, wrapped
/// (design `docs/design/patcher.md` §3, §4).
///
/// A patcher's graph **and** its layout both live in the engine dump (node
/// positions ride in the object GUI properties the shipped gateway already
/// writes), so Phi keeps no parallel graph model: the [dump] *is* the state.
/// Save refreshes the engine dump into this payload; load hands it back to the
/// engine to `parseJson`. The registry/store add the usual
/// `kind`/`version`/`name`/`references` envelope around it.
///
/// Alongside the dump the payload carries the patcher's **source placement**
/// ([placement], design §4 role 1, §8): the `mix.` bus this patch mounts onto as
/// a `Sound` when it runs, or `null` when it is not placed as a source. Placement
/// persists; whether the source is *currently* running does not (a loaded project
/// starts silent, consistent with clips). The placement is a **soft** pointer,
/// not a tracked registry reference — a patch still references no entity through
/// the back-reference index — so a stale bus degrades gracefully at reconcile
/// time rather than blocking a delete (issue #220).
///
/// Immutable and compared by value — the whole opaque dump structurally, plus the
/// placement — so a round-trip through the codec and store asserts identity.
class PatchPayload {
  /// Wraps the decoded engine [dump] (the JSON `dumpJson` produces) with an
  /// optional source [placement] bus.
  const PatchPayload({this.dump = const {}, this.placement});

  /// Reads a payload from a decoded `{dump: …, placement: …}` map. A missing or
  /// non-map `dump` yields an empty patch; a missing or unparseable `placement`
  /// leaves the patch unplaced.
  factory PatchPayload.fromJson(Map<String, Object?> json) {
    final placement = json['placement'];
    return PatchPayload(
      dump: (json['dump'] as Map?)?.cast<String, Object?>() ?? const {},
      placement: placement is String ? EntityAddress.tryParse(placement) : null,
    );
  }

  /// An empty patch — no objects, no cables, unplaced.
  static const PatchPayload empty = PatchPayload();

  /// The engine dump, decoded to a JSON map. Opaque to Phi: the domain never
  /// interprets its shape, it only carries it between save and load.
  final Map<String, Object?> dump;

  /// The `mix.` bus this patcher mounts onto as a source `Sound` when running, or
  /// `null` when it is not placed as a source (design §4 role 1). A soft pointer:
  /// a bus that no longer exists is degraded to unplaced at reconcile time.
  final EntityAddress? placement;

  /// A copy with the [dump] replaced (the placement carried over) — how a save
  /// swaps in the freshly-dumped engine state without disturbing placement.
  PatchPayload withDump(Map<String, Object?> dump) =>
      PatchPayload(dump: dump, placement: placement);

  /// A copy placed on [placement] (or unplaced when `null`), the dump carried
  /// over — how a placement gesture records the chosen source bus.
  PatchPayload withPlacement(EntityAddress? placement) =>
      PatchPayload(dump: dump, placement: placement);

  /// The payload as a JSON map. The `placement` key is emitted only when placed,
  /// so an unplaced patch re-encodes byte-identically to a bare `{dump: …}`.
  Map<String, Object?> toJson() => {
    'dump': dump,
    if (placement != null) 'placement': placement!.format(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PatchPayload &&
          other.placement == placement &&
          _jsonEqual(other.dump, dump));

  @override
  int get hashCode => Object.hash(placement, _jsonHash(dump));

  @override
  String toString() => 'PatchPayload(dump: $dump, placement: $placement)';

  /// Deep, order-independent equality over decoded-JSON values (maps, lists and
  /// primitives) — the dump is opaque, so identity is a structural compare.
  static bool _jsonEqual(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final entry in a.entries) {
        if (!b.containsKey(entry.key)) return false;
        if (!_jsonEqual(entry.value, b[entry.key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_jsonEqual(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  /// Order-independent hash matching [_jsonEqual].
  static int _jsonHash(Object? value) {
    if (value is Map) {
      var hash = 0;
      for (final entry in value.entries) {
        hash ^= Object.hash(entry.key, _jsonHash(entry.value));
      }
      return hash;
    }
    if (value is List) {
      return Object.hashAll(value.map(_jsonHash));
    }
    return value.hashCode;
  }
}
