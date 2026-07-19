import 'fm_operator.dart';
import 'synth_definition.dart';
import 'synth_kind.dart';

/// A `synth.` definition of kind [SynthKind.fm] — a DX7-class 6-operator FM voice
/// (design `docs/design/racks-and-voices.md` §4).
///
/// The recipe is **a bank asset reference plus a patch index**: [bankAsset] names
/// a `.syx` bank (a project-relative path, per §4; `null` uses the engine's
/// built-in test patch) and [patchIndex] selects a voice within it. On top of the
/// selected patch sit *optional overrides* — [algorithm], [feedback], [transpose]
/// and a sparse list of per-[operators] tweaks — left `null`/empty when the patch
/// is played verbatim. A plain, immutable value type.
class FmSynth extends SynthDefinition {
  /// Builds an FM definition. With no [bankAsset] and no overrides it is the
  /// engine's built-in patch — a valid, audible starting point.
  const FmSynth({
    this.bankAsset,
    this.patchIndex = 0,
    this.algorithm,
    this.feedback,
    this.transpose,
    this.operators = const [],
    this.voiceCount = 8,
  });

  /// Reads an FM definition from a decoded map, defaulting missing keys and
  /// leaving absent overrides `null`/empty.
  factory FmSynth.fromJson(Map<String, Object?> json) => FmSynth(
    bankAsset: json['bankAsset'] as String?,
    patchIndex: (json['patchIndex'] as num?)?.toInt() ?? 0,
    algorithm: (json['algorithm'] as num?)?.toInt(),
    feedback: (json['feedback'] as num?)?.toInt(),
    transpose: (json['transpose'] as num?)?.toInt(),
    operators: [
      for (final op in (json['operators'] as List<Object?>? ?? const []))
        FmOperator.fromJson((op as Map).cast<String, Object?>()),
    ],
    voiceCount: (json['voiceCount'] as num?)?.toInt() ?? 8,
  );

  /// The `.syx` bank's project-relative path, or `null` for the built-in patch.
  final String? bankAsset;

  /// The patch index selected within [bankAsset].
  final int patchIndex;

  /// Optional algorithm override (`0..31`), or `null` to keep the patch's.
  final int? algorithm;

  /// Optional feedback override (`0..7`), or `null` to keep the patch's.
  final int? feedback;

  /// Optional transpose override in semitones, or `null` to keep the patch's.
  final int? transpose;

  /// Sparse per-operator overrides — empty when the patch's operators stand.
  final List<FmOperator> operators;

  @override
  SynthKind get kind => SynthKind.fm;

  @override
  final int voiceCount;

  FmSynth copyWith({
    String? bankAsset,
    int? patchIndex,
    int? algorithm,
    int? feedback,
    int? transpose,
    List<FmOperator>? operators,
    int? voiceCount,
  }) => FmSynth(
    bankAsset: bankAsset ?? this.bankAsset,
    patchIndex: patchIndex ?? this.patchIndex,
    algorithm: algorithm ?? this.algorithm,
    feedback: feedback ?? this.feedback,
    transpose: transpose ?? this.transpose,
    operators: operators ?? this.operators,
    voiceCount: voiceCount ?? this.voiceCount,
  );

  /// The definition as its JSON map. `null` overrides are omitted so the payload
  /// carries only what the recipe actually pins; keys are in a stable order.
  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (bankAsset != null) 'bankAsset': bankAsset,
    'patchIndex': patchIndex,
    if (algorithm != null) 'algorithm': algorithm,
    if (feedback != null) 'feedback': feedback,
    if (transpose != null) 'transpose': transpose,
    'operators': [for (final op in operators) op.toJson()],
    'voiceCount': voiceCount,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FmSynth &&
          other.bankAsset == bankAsset &&
          other.patchIndex == patchIndex &&
          other.algorithm == algorithm &&
          other.feedback == feedback &&
          other.transpose == transpose &&
          _operatorsEqual(other.operators, operators) &&
          other.voiceCount == voiceCount;

  @override
  int get hashCode => Object.hash(
    bankAsset,
    patchIndex,
    algorithm,
    feedback,
    transpose,
    Object.hashAll(operators),
    voiceCount,
  );

  @override
  String toString() =>
      'FmSynth(bankAsset: $bankAsset, patchIndex: $patchIndex, '
      'algorithm: $algorithm, feedback: $feedback, transpose: $transpose, '
      'operators: $operators, voiceCount: $voiceCount)';

  /// Element-wise operator-list equality (the domain has no `listEquals`).
  static bool _operatorsEqual(List<FmOperator> a, List<FmOperator> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
