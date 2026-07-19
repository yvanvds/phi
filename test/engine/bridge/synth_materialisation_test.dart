import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/synth/fm_operator.dart';
import 'package:phi/domain/synth/fm_synth.dart';
import 'package:phi/domain/synth/sample_recipe.dart';
import 'package:phi/domain/synth/sampler_synth.dart';
import 'package:phi/domain/synth/sine_synth.dart';
import 'package:phi/domain/synth/va_filter.dart';
import 'package:phi/domain/synth/va_synth.dart';
import 'package:phi/engine/bridge/synth_materialisation.dart';

void main() {
  group('SynthMaterialisation.needsRematerialise', () {
    test('a kind change always rebuilds', () {
      expect(
        SynthMaterialisation.needsRematerialise(
          const SineSynth(),
          const VaSynth(),
        ),
        isTrue,
      );
    });

    test('a voice-count change rebuilds for every kind', () {
      expect(
        SynthMaterialisation.needsRematerialise(
          const SineSynth(voiceCount: 8),
          const SineSynth(voiceCount: 16),
        ),
        isTrue,
      );
      expect(
        SynthMaterialisation.needsRematerialise(
          const VaSynth(voiceCount: 8),
          const VaSynth(voiceCount: 4),
        ),
        isTrue,
      );
      expect(
        SynthMaterialisation.needsRematerialise(
          const FmSynth(voiceCount: 8),
          const FmSynth(voiceCount: 6),
        ),
        isTrue,
      );
      expect(
        SynthMaterialisation.needsRematerialise(
          const SamplerSynth(voiceCount: 8),
          const SamplerSynth(voiceCount: 2),
        ),
        isTrue,
      );
    });

    test('an identical sine definition needs no rebuild', () {
      expect(
        SynthMaterialisation.needsRematerialise(
          const SineSynth(),
          const SineSynth(),
        ),
        isFalse,
      );
    });

    test('a VA panel-param edit is live (no rebuild)', () {
      expect(
        SynthMaterialisation.needsRematerialise(
          const VaSynth(filter: VaFilter(cutoff: 20000)),
          const VaSynth(filter: VaFilter(cutoff: 800)),
        ),
        isFalse,
      );
    });

    test('an FM patch/override edit within the same bank is live', () {
      expect(
        SynthMaterialisation.needsRematerialise(
          const FmSynth(bankAsset: 'assets/bells.syx', patchIndex: 0),
          const FmSynth(
            bankAsset: 'assets/bells.syx',
            patchIndex: 12,
            feedback: 5,
            operators: [FmOperator(op: 0, outputLevel: 80)],
          ),
        ),
        isFalse,
      );
    });

    test('an FM bank swap rebuilds', () {
      expect(
        SynthMaterialisation.needsRematerialise(
          const FmSynth(bankAsset: 'assets/bells.syx'),
          const FmSynth(bankAsset: 'assets/brass.syx'),
        ),
        isTrue,
      );
      // Gaining or losing a bank is a swap too.
      expect(
        SynthMaterialisation.needsRematerialise(
          const FmSynth(),
          const FmSynth(bankAsset: 'assets/brass.syx'),
        ),
        isTrue,
      );
    });

    test('a sampler SFZ swap rebuilds', () {
      expect(
        SynthMaterialisation.needsRematerialise(
          const SamplerSynth(sfzAsset: 'assets/piano.sfz'),
          const SamplerSynth(sfzAsset: 'assets/rhodes.sfz'),
        ),
        isTrue,
      );
    });

    test('a sampler single-sample recipe change rebuilds', () {
      expect(
        SynthMaterialisation.needsRematerialise(
          const SamplerSynth(recipe: SampleRecipe(file: 'assets/kick.wav')),
          const SamplerSynth(
            recipe: SampleRecipe(file: 'assets/kick.wav', root: 48),
          ),
        ),
        isTrue,
      );
    });

    test('switching a sampler between SFZ and single-sample rebuilds', () {
      expect(
        SynthMaterialisation.needsRematerialise(
          const SamplerSynth(sfzAsset: 'assets/piano.sfz'),
          const SamplerSynth(recipe: SampleRecipe(file: 'assets/kick.wav')),
        ),
        isTrue,
      );
    });
  });
}
