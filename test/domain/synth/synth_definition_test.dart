import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/synth/fm_synth.dart';
import 'package:phi/domain/synth/sample_recipe.dart';
import 'package:phi/domain/synth/sampler_synth.dart';
import 'package:phi/domain/synth/sine_synth.dart';
import 'package:phi/domain/synth/synth_definition.dart';
import 'package:phi/domain/synth/va_synth.dart';

void main() {
  group('SynthDefinition.fromJson dispatch', () {
    final definitions = <SynthDefinition>[
      const SineSynth(voiceCount: 3),
      const VaSynth(gain: 0.5, voiceCount: 5),
      const FmSynth(bankAsset: 'a.syx', patchIndex: 7),
      const SamplerSynth(recipe: SampleRecipe(file: 'x.wav')),
    ];

    test('every kind round-trips through the base factory by its kind tag', () {
      for (final definition in definitions) {
        final decoded = SynthDefinition.fromJson(definition.toJson());
        expect(decoded, definition);
        expect(decoded.kind, definition.kind);
        expect(decoded.runtimeType, definition.runtimeType);
      }
    });

    test('a missing kind tag throws', () {
      expect(
        () => SynthDefinition.fromJson(const {'voiceCount': 4}),
        throwsFormatException,
      );
    });

    test('an unknown kind tag throws', () {
      expect(
        () => SynthDefinition.fromJson(const {'kind': 'wavetableGranular'}),
        throwsFormatException,
      );
    });
  });
}
