/// The payload of a `patch.` registry entity — the engine's `dumpJson`, wrapped
/// (design `docs/design/patcher.md` §3).
///
/// A patcher's graph **and** its layout both live in the engine dump (node
/// positions ride in the object GUI properties the shipped gateway already
/// writes), so Phi keeps no parallel graph model: the [dump] *is* the state.
/// Save refreshes the engine dump into this payload; load hands it back to the
/// engine to `parseJson`. The registry/store add the usual
/// `kind`/`version`/`name`/`references` envelope around it.
///
/// A patch references no other registry entity (its inner nodes are engine
/// objects, not addresses), so the payload is **not** a `ReferenceSource`; a
/// placement that references *this* patch (an `fx.`/`voice.` role) declares that
/// edge on its own side.
///
/// Immutable and compared by value — the whole opaque dump structurally — so a
/// round-trip through the codec and store asserts identity.
class PatchPayload {
  /// Wraps the decoded engine [dump] (the JSON `dumpJson` produces).
  const PatchPayload({this.dump = const {}});

  /// Reads a payload from a decoded `{dump: …}` map. A missing or non-map
  /// `dump` yields an empty patch.
  factory PatchPayload.fromJson(Map<String, Object?> json) => PatchPayload(
    dump: (json['dump'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  /// An empty patch — no objects, no cables.
  static const PatchPayload empty = PatchPayload();

  /// The engine dump, decoded to a JSON map. Opaque to Phi: the domain never
  /// interprets its shape, it only carries it between save and load.
  final Map<String, Object?> dump;

  /// A copy with the [dump] replaced — how a save swaps in the freshly-dumped
  /// engine state.
  PatchPayload withDump(Map<String, Object?> dump) => PatchPayload(dump: dump);

  /// The payload as a `{dump: …}` JSON map.
  Map<String, Object?> toJson() => {'dump': dump};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PatchPayload && _jsonEqual(other.dump, dump));

  @override
  int get hashCode => _jsonHash(dump);

  @override
  String toString() => 'PatchPayload(dump: $dump)';

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
