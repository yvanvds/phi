import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/synth/sine_synth.dart';
import 'package:phi/domain/synth/synth_kind.dart';

void main() {
  group('SineSynth', () {
    test('is of kind sine', () {
      expect(const SineSynth().kind, SynthKind.sine);
    });

    test('round-trips through JSON', () {
      const synth = SineSynth(voiceCount: 4);
      expect(SineSynth.fromJson(synth.toJson()), synth);
    });

    test('toJson tags the kind and carries only the voice count', () {
      expect(const SineSynth(voiceCount: 6).toJson(), {
        'kind': 'sine',
        'voiceCount': 6,
      });
    });

    test('fromJson defaults the voice count', () {
      expect(SineSynth.fromJson(const {'kind': 'sine'}), const SineSynth());
    });

    test('equality is by value', () {
      expect(const SineSynth(), const SineSynth());
      expect(const SineSynth(voiceCount: 2), isNot(const SineSynth()));
    });
  });
}
