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
/// enforced through the back-reference index. An `fx.` payload references no other
/// entity, so it is *not* a `ReferenceSource`.
///
/// A plain, immutable value type: it (de)serialises to a JSON map and compares by
/// value (params order-independently) so a round-trip is easy to assert.
class FxDefinition {
  /// Builds an effect of [kind] with an optional [params] map (defaults to none).
  const FxDefinition({required this.kind, this.params = const {}});

  /// Reads an effect from a decoded map. Throws a [FormatException] on a
  /// missing/unknown `kind`. Missing `params` default to empty; each value is
  /// read as a double.
  factory FxDefinition.fromJson(Map<String, Object?> json) => FxDefinition(
    kind: _kindByName(json['kind'] as String?),
    params: {
      for (final entry
          in ((json['params'] as Map?)?.cast<String, Object?>() ??
                  const <String, Object?>{})
              .entries)
        entry.key: (entry.value as num).toDouble(),
    },
  );

  /// Which effect this instance is.
  final FxKind kind;

  /// The effect's parameters as a `name → value` map. Continuous knobs and
  /// discrete counts alike are held as doubles; the gateway rounds where a param
  /// is integral (e.g. delay taps).
  final Map<String, double> params;

  /// A copy with [kind] and/or [params] replaced.
  FxDefinition copyWith({FxKind? kind, Map<String, double>? params}) =>
      FxDefinition(kind: kind ?? this.kind, params: params ?? this.params);

  /// A copy with one param set (or added) — the single-knob edit the fx panel
  /// and live code make.
  FxDefinition withParam(String name, double value) =>
      FxDefinition(kind: kind, params: {...params, name: value});

  /// The effect as its JSON map. Params are emitted in sorted key order so an
  /// unchanged instance re-encodes byte-identically.
  Map<String, Object?> toJson() {
    final keys = params.keys.toList()..sort();
    return {
      'kind': kind.name,
      'params': {for (final key in keys) key: params[key]},
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
          _paramsEqual(other.params, params);

  @override
  int get hashCode {
    var paramsHash = 0;
    for (final entry in params.entries) {
      paramsHash ^= Object.hash(entry.key, entry.value);
    }
    return Object.hash(kind, paramsHash);
  }

  @override
  String toString() => 'FxDefinition(kind: ${kind.name}, params: $params)';

  static bool _paramsEqual(Map<String, double> a, Map<String, double> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
