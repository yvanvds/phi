import 'sample_recipe.dart';
import 'synth_definition.dart';
import 'synth_kind.dart';

/// A `synth.` definition of kind [SynthKind.sampler] — an SFZ / single-sample
/// sampler voice (design `docs/design/racks-and-voices.md` §4).
///
/// Two mutually exclusive recipes: an [sfzAsset] (a project-relative `.sfz` path,
/// per §4) *or* a single-sample [recipe]. Exactly one is set; a definition with
/// neither is an empty sampler the editor fills in. A plain, immutable value
/// type.
class SamplerSynth extends SynthDefinition {
  /// Builds a sampler from an [sfzAsset], a single-sample [recipe], or neither.
  /// Supplying both is a programming error — a sampler plays one source.
  const SamplerSynth({this.sfzAsset, this.recipe, this.voiceCount = 8})
    : assert(
        sfzAsset == null || recipe == null,
        'A sampler plays either an SFZ asset or a single-sample recipe, '
        'not both.',
      );

  /// Reads a sampler definition from a decoded map. Prefers `sfz` when both keys
  /// are present so a hand-edited file never trips the both-set assertion.
  factory SamplerSynth.fromJson(Map<String, Object?> json) {
    final sfz = json['sfz'] as String?;
    final recipeJson = json['recipe'];
    return SamplerSynth(
      sfzAsset: sfz,
      recipe: sfz == null && recipeJson != null
          ? SampleRecipe.fromJson((recipeJson as Map).cast<String, Object?>())
          : null,
      voiceCount: (json['voiceCount'] as num?)?.toInt() ?? 8,
    );
  }

  /// The `.sfz` instrument's project-relative path, or `null` for the
  /// single-sample [recipe] (or an empty sampler).
  final String? sfzAsset;

  /// The single-sample recipe, or `null` when an [sfzAsset] is used (or empty).
  final SampleRecipe? recipe;

  @override
  SynthKind get kind => SynthKind.sampler;

  @override
  final int voiceCount;

  /// A copy with an [sfzAsset], clearing any single-sample [recipe] so the two
  /// sources stay mutually exclusive.
  SamplerSynth withSfz(String sfzAsset, {int? voiceCount}) => SamplerSynth(
    sfzAsset: sfzAsset,
    voiceCount: voiceCount ?? this.voiceCount,
  );

  /// A copy with a single-sample [recipe], clearing any [sfzAsset].
  SamplerSynth withRecipe(SampleRecipe recipe, {int? voiceCount}) =>
      SamplerSynth(recipe: recipe, voiceCount: voiceCount ?? this.voiceCount);

  /// The definition as its JSON map. Only the source that is set is emitted, so
  /// the payload names one instrument; keys are in a stable order.
  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (sfzAsset != null) 'sfz': sfzAsset,
    if (recipe != null) 'recipe': recipe!.toJson(),
    'voiceCount': voiceCount,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SamplerSynth &&
          other.sfzAsset == sfzAsset &&
          other.recipe == recipe &&
          other.voiceCount == voiceCount;

  @override
  int get hashCode => Object.hash(sfzAsset, recipe, voiceCount);

  @override
  String toString() =>
      'SamplerSynth(sfzAsset: $sfzAsset, recipe: $recipe, '
      'voiceCount: $voiceCount)';
}
