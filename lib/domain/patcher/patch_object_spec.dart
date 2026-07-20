import 'patch_point.dart';

/// Everything needed to (re)create one patcher object: its [type], creation
/// [args], canvas [position], and current creation-parameter [params].
///
/// It is both the descriptor an *add-object* gesture carries and the snapshot a
/// *delete-object* gesture captures so its undo can restore the object exactly
/// (design `docs/design/patcher.md` §3). The engine dump remains the persisted
/// source of truth — this is the transient shape the gesture command layer and
/// the gateway speak, never a second stored graph model.
///
/// A plain, immutable value type: it (de)serialises to a JSON map and compares
/// by value (params order-independently).
class PatchObjectSpec {
  /// Builds a spec for an object of [type], with optional creation [args],
  /// [position] (defaults to the origin), and [params] (defaults to none).
  const PatchObjectSpec({
    required this.type,
    this.args = '',
    this.position = const PatchPoint(0, 0),
    this.params = const {},
  });

  /// Reads a spec from a decoded map. A missing `type` throws a
  /// [FormatException]; missing `args`/`position`/`params` take their defaults.
  factory PatchObjectSpec.fromJson(Map<String, Object?> json) {
    final type = json['type'];
    if (type is! String) {
      throw const FormatException('A patch object spec needs a "type".');
    }
    final position = json['position'];
    return PatchObjectSpec(
      type: type,
      args: json['args'] as String? ?? '',
      position: position is Map
          ? PatchPoint.fromJson(position.cast<String, Object?>())
          : const PatchPoint(0, 0),
      params: {
        for (final entry
            in ((json['params'] as Map?)?.cast<String, Object?>() ??
                    const <String, Object?>{})
                .entries)
          entry.key: (entry.value as num).toDouble(),
      },
    );
  }

  /// The object type — one of `package:yse`'s `Obj.*` constants (e.g. `'~sine'`,
  /// `'.slider'`).
  final String type;

  /// The creation-time argument string, as the engine's `createObject` takes it.
  final String args;

  /// The object's on-canvas position.
  final PatchPoint position;

  /// The object's creation parameters as a `name → value` map. Seeds the
  /// object's initial state so a later param edit always has a prior value to
  /// restore on undo.
  final Map<String, double> params;

  /// A copy with the given fields replaced.
  PatchObjectSpec copyWith({
    String? type,
    String? args,
    PatchPoint? position,
    Map<String, double>? params,
  }) => PatchObjectSpec(
    type: type ?? this.type,
    args: args ?? this.args,
    position: position ?? this.position,
    params: params ?? this.params,
  );

  /// The spec as a JSON map. Params are emitted in sorted key order so an
  /// unchanged spec re-encodes byte-identically.
  Map<String, Object?> toJson() {
    final keys = params.keys.toList()..sort();
    return {
      'type': type,
      'args': args,
      'position': position.toJson(),
      'params': {for (final key in keys) key: params[key]},
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PatchObjectSpec &&
          other.type == type &&
          other.args == args &&
          other.position == position &&
          _paramsEqual(other.params, params));

  @override
  int get hashCode {
    var paramsHash = 0;
    for (final entry in params.entries) {
      paramsHash ^= Object.hash(entry.key, entry.value);
    }
    return Object.hash(type, args, position, paramsHash);
  }

  @override
  String toString() =>
      'PatchObjectSpec(type: $type, args: $args, position: $position, '
      'params: $params)';

  static bool _paramsEqual(Map<String, double> a, Map<String, double> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
