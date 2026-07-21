import '../project/entity_address.dart';
import '../project/reference_source.dart';
import 'fx_kind.dart';

/// The payload of an `fx.` registry entity — **one effect instance** (design
/// `docs/design/racks-and-voices.md` §5).
///
/// An effect is its [kind] plus a flat bag of named [params] (e.g.
/// `fx.big_delay` → a `lowpassDelay` with `taps`, `impact`, `feedback`). Live code
/// addresses a param by name (`fx.big_delay.impact = 0.5`), and the gateway maps
/// kind + params onto a linked `DspObject` chain — so the domain keeps the params
/// as a plain `name → value` map rather than a per-effect typed panel, and the
/// engine layer owns the meaning of each key.
///
/// **Placement is not stored here.** Which mix bus an instance sits on lives in
/// that bus's `inserts` list (design §5); an instance sits on at most one bus,
/// enforced through the back-reference index.
///
/// **The patcher-insert kind carries a `patch.` reference** ([patch], design
/// `docs/design/patcher.md` §4 role 2). An `fx.` entity of [FxKind.patcherInsert]
/// wraps a `patch.` entity — the engine materialises it as
/// `DspObject.patcherInsert` borrowing that patch's live native graph — so the
/// wrapper points at its patch by address. That makes `fx → patch` an edge in the
/// registry back-reference index, so a [ReferenceSource]: deleting the patch lists
/// its insert wrappers, and renaming it refactors the reference. Every other kind
/// references nothing ([references] is then empty), exactly as before.
///
/// A plain, immutable value type: it (de)serialises to a JSON map and compares by
/// value (params order-independently) so a round-trip is easy to assert.
class FxDefinition implements ReferenceSource {
  /// Builds an effect of [kind] with an optional [params] map (defaults to none)
  /// and, for [FxKind.patcherInsert], the wrapped [patch] entity address.
  const FxDefinition({required this.kind, this.params = const {}, this.patch});

  /// Reads an effect from a decoded map. Throws a [FormatException] on a
  /// missing/unknown `kind`. Missing `params` default to empty; each value is
  /// read as a double. An optional dotted `patch` address is parsed for the
  /// patcher-insert kind (ignored/unset for others).
  factory FxDefinition.fromJson(Map<String, Object?> json) => FxDefinition(
    kind: _kindByName(json['kind'] as String?),
    params: {
      for (final entry
          in ((json['params'] as Map?)?.cast<String, Object?>() ??
                  const <String, Object?>{})
              .entries)
        entry.key: (entry.value as num).toDouble(),
    },
    patch: switch (json['patch']) {
      final String p => EntityAddress.tryParse(p),
      _ => null,
    },
  );

  /// Which effect this instance is.
  final FxKind kind;

  /// The effect's parameters as a `name → value` map. Continuous knobs and
  /// discrete counts alike are held as doubles; the gateway rounds where a param
  /// is integral (e.g. delay taps).
  final Map<String, double> params;

  /// The `patch.` entity this effect wraps, for [FxKind.patcherInsert]; `null`
  /// for every other kind. The engine borrows that patch's live native patcher
  /// into a `DspObject.patcherInsert` on the placing bus's chain, so edits to the
  /// patch are heard live through the insert (design `docs/design/patcher.md` §4).
  final EntityAddress? patch;

  /// A copy with [kind], [params] and/or [patch] replaced.
  FxDefinition copyWith({
    FxKind? kind,
    Map<String, double>? params,
    EntityAddress? patch,
  }) => FxDefinition(
    kind: kind ?? this.kind,
    params: params ?? this.params,
    patch: patch ?? this.patch,
  );

  /// A copy with one param set (or added) — the single-knob edit the fx panel
  /// and live code make. Keeps the wrapped [patch].
  FxDefinition withParam(String name, double value) =>
      FxDefinition(kind: kind, params: {...params, name: value}, patch: patch);

  /// The `patch.` addresses this effect points at — the wrapped patch for a
  /// patcher insert, none for any other kind. Feeds the registry back-reference
  /// index (design `docs/design/patcher.md` §4).
  @override
  Set<EntityAddress> get references => {?patch};

  /// A copy with a reference to [from] repointed to [to] — the refactor a wrapped
  /// patch's rename/move triggers. Applying the inverse restores the original, so
  /// undo round-trips.
  @override
  FxDefinition withReferenceUpdated(EntityAddress from, EntityAddress to) =>
      FxDefinition(
        kind: kind,
        params: params,
        patch: patch == from ? to : patch,
      );

  /// The effect as its JSON map. Params are emitted in sorted key order so an
  /// unchanged instance re-encodes byte-identically; the wrapped patch is emitted
  /// (in dotted form) only when set.
  Map<String, Object?> toJson() {
    final keys = params.keys.toList()..sort();
    return {
      'kind': kind.name,
      'params': {for (final key in keys) key: params[key]},
      if (patch != null) 'patch': patch!.format(),
    };
  }

  static FxKind _kindByName(String? name) {
    for (final k in FxKind.values) {
      if (k.name == name) return k;
    }
    throw FormatException('Unknown fx kind: "$name".');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FxDefinition &&
          other.kind == kind &&
          other.patch == patch &&
          _paramsEqual(other.params, params);

  @override
  int get hashCode {
    var paramsHash = 0;
    for (final entry in params.entries) {
      paramsHash ^= Object.hash(entry.key, entry.value);
    }
    return Object.hash(kind, patch, paramsHash);
  }

  @override
  String toString() =>
      'FxDefinition(kind: ${kind.name}, params: $params, patch: $patch)';

  static bool _paramsEqual(Map<String, double> a, Map<String, double> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
