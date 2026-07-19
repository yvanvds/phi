import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/synth/sample_recipe.dart';
import 'package:phi/domain/synth/sampler_synth.dart';
import 'package:phi/domain/synth/synth_kind.dart';

void main() {
  group('SamplerSynth', () {
    test('is of kind sampler', () {
      expect(const SamplerSynth().kind, SynthKind.sampler);
    });

    test('round-trips an SFZ-backed sampler', () {
      const synth = SamplerSynth(sfzAsset: 'assets/piano.sfz', voiceCount: 16);
      expect(SamplerSynth.fromJson(synth.toJson()), synth);
    });

    test('round-trips a single-sample sampler', () {
      const synth = SamplerSynth(
        recipe: SampleRecipe(file: 'assets/clap.wav', root: 48),
        voiceCount: 4,
      );
      expect(SamplerSynth.fromJson(synth.toJson()), synth);
    });

    test('round-trips an empty sampler', () {
      const synth = SamplerSynth();
      expect(SamplerSynth.fromJson(synth.toJson()), synth);
    });

    test('an SFZ asset and a recipe are mutually exclusive', () {
      expect(
        () => SamplerSynth(
          sfzAsset: 'a.sfz',
          recipe: const SampleRecipe(file: 'b.wav'),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('toJson emits only the source that is set', () {
      expect(const SamplerSynth(sfzAsset: 'a.sfz').toJson(), {
        'kind': 'sampler',
        'sfz': 'a.sfz',
        'voiceCount': 8,
      });
    });

    test('fromJson prefers sfz when a file mixes both keys', () {
      final synth = SamplerSynth.fromJson(const {
        'kind': 'sampler',
        'sfz': 'a.sfz',
        'recipe': {'file': 'b.wav'},
      });
      expect(synth.sfzAsset, 'a.sfz');
      expect(synth.recipe, isNull);
    });

    test('withSfz and withRecipe swap the source exclusively', () {
      const sfz = SamplerSynth(sfzAsset: 'a.sfz');
      final recipe = sfz.withRecipe(const SampleRecipe(file: 'b.wav'));
      expect(recipe.sfzAsset, isNull);
      expect(recipe.recipe, const SampleRecipe(file: 'b.wav'));
      expect(recipe.withSfz('c.sfz').recipe, isNull);
    });

    test('equality is by value', () {
      expect(const SamplerSynth(), const SamplerSynth());
      expect(
        const SamplerSynth(sfzAsset: 'a.sfz'),
        isNot(const SamplerSynth(sfzAsset: 'b.sfz')),
      );
    });
  });
}
