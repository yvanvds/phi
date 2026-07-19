/// A per-operator override for an FM voice (design
/// `docs/design/racks-and-voices.md` §4 — "optional … per-op overrides").
///
/// A DX7-class FM voice has six operators, addressed by [op] in `[0, 5]`. A patch
/// selected from a bank already sets every operator; an [FmOperator] override
/// re-dials the headline params of one of them: whether it is [enabled], its
/// [outputLevel] (`0..99`), its coarse / fine frequency ratio ([freqCoarse]
/// `0..31`, [freqFine] `0..99`), and its [detune] (`0..14`, centred at 7). Values
/// stay in the engine's integer DX7 domain — the gateway passes them straight to
/// `setFmOp*`. A plain, immutable value type.
class FmOperator {
  /// Builds an operator override for [op] (`0..5`). Defaults are a neutral, fully
  /// open operator at a 1:1 ratio with no detune.
  const FmOperator({
    required this.op,
    this.enabled = true,
    this.outputLevel = 99,
    this.freqCoarse = 1,
    this.freqFine = 0,
    this.detune = 7,
  });

  /// Reads an operator from a decoded map, defaulting any missing key. Throws a
  /// [FormatException] if `op` is absent — an override with no target operator is
  /// meaningless.
  factory FmOperator.fromJson(Map<String, Object?> json) {
    final op = (json['op'] as num?)?.toInt();
    if (op == null) {
      throw const FormatException(
        'An FM operator override needs an "op" index.',
      );
    }
    return FmOperator(
      op: op,
      enabled: json['enabled'] as bool? ?? true,
      outputLevel: (json['outputLevel'] as num?)?.toInt() ?? 99,
      freqCoarse: (json['freqCoarse'] as num?)?.toInt() ?? 1,
      freqFine: (json['freqFine'] as num?)?.toInt() ?? 0,
      detune: (json['detune'] as num?)?.toInt() ?? 7,
    );
  }

  /// The operator index this override targets, in `[0, 5]`.
  final int op;

  /// Whether the operator is enabled.
  final bool enabled;

  /// Output level in `[0, 99]`.
  final int outputLevel;

  /// Coarse frequency ratio in `[0, 31]`.
  final int freqCoarse;

  /// Fine frequency ratio in `[0, 99]`.
  final int freqFine;

  /// Detune in `[0, 14]` (7 = centred).
  final int detune;

  FmOperator copyWith({
    int? op,
    bool? enabled,
    int? outputLevel,
    int? freqCoarse,
    int? freqFine,
    int? detune,
  }) => FmOperator(
    op: op ?? this.op,
    enabled: enabled ?? this.enabled,
    outputLevel: outputLevel ?? this.outputLevel,
    freqCoarse: freqCoarse ?? this.freqCoarse,
    freqFine: freqFine ?? this.freqFine,
    detune: detune ?? this.detune,
  );

  /// The operator as its JSON map, keys in a stable order.
  Map<String, Object?> toJson() => {
    'op': op,
    'enabled': enabled,
    'outputLevel': outputLevel,
    'freqCoarse': freqCoarse,
    'freqFine': freqFine,
    'detune': detune,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FmOperator &&
          other.op == op &&
          other.enabled == enabled &&
          other.outputLevel == outputLevel &&
          other.freqCoarse == freqCoarse &&
          other.freqFine == freqFine &&
          other.detune == detune;

  @override
  int get hashCode =>
      Object.hash(op, enabled, outputLevel, freqCoarse, freqFine, detune);

  @override
  String toString() =>
      'FmOperator(op: $op, enabled: $enabled, outputLevel: $outputLevel, '
      'freqCoarse: $freqCoarse, freqFine: $freqFine, detune: $detune)';
}
