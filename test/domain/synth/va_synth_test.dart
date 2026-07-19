import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/synth/adsr_envelope.dart';
import 'package:phi/domain/synth/lfo_type.dart';
import 'package:phi/domain/synth/synth_kind.dart';
import 'package:phi/domain/synth/va_filter.dart';
import 'package:phi/domain/synth/va_lfo.dart';
import 'package:phi/domain/synth/va_oscillator.dart';
import 'package:phi/domain/synth/va_synth.dart';
import 'package:phi/domain/synth/va_waveform.dart';

void main() {
  // A fully-dialled patch touching every section — the round-trip identity case.
  const rich = VaSynth(
    oscillators: [
      VaOscillator(wave: VaWaveform.saw, detune: -0.1, level: 0.9),
      VaOscillator(wave: VaWaveform.pulse, detune: 7.0, pulseWidth: 0.25),
    ],
    wavetablePosition: 0.6,
    filter: VaFilter(cutoff: 1200.0, resonance: 0.4, envAmount: 1.5),
    ampEnvelope: AdsrEnvelope(attack: 0.02, release: 0.9),
    ampVelAmount: 0.7,
    filterEnvelope: AdsrEnvelope(attack: 0.0, decay: 0.5, sustain: 0.0),
    lfo: VaLfo(type: LfoType.triangle, rate: 5.0, toCutoff: 1.0),
    gain: 0.8,
    voiceCount: 6,
  );

  group('VaSynth', () {
    test('is of kind va', () {
      expect(const VaSynth().kind, SynthKind.va);
    });

    test('round-trips the full panel through JSON', () {
      expect(VaSynth.fromJson(rich.toJson()), rich);
    });

    test('toJson tags the kind', () {
      expect(rich.toJson()['kind'], 'va');
    });

    test('a default VA still round-trips', () {
      const synth = VaSynth();
      expect(VaSynth.fromJson(synth.toJson()), synth);
    });

    test('fromJson falls back to a single oscillator when none are given', () {
      final synth = VaSynth.fromJson(const {'kind': 'va', 'oscillators': []});
      expect(synth.oscillators, const [VaOscillator()]);
    });

    test('fromJson fills every section for a bare map', () {
      expect(VaSynth.fromJson(const {'kind': 'va'}), const VaSynth());
    });

    test('copyWith replaces only the given fields', () {
      const synth = VaSynth();
      expect(synth.copyWith(gain: 0.5).gain, 0.5);
      expect(synth.copyWith(gain: 0.5).voiceCount, synth.voiceCount);
    });

    test('equality reaches into the oscillator list and every section', () {
      expect(const VaSynth(), const VaSynth());
      expect(
        const VaSynth(oscillators: [VaOscillator(level: 0.5)]),
        isNot(const VaSynth()),
      );
      expect(const VaSynth(gain: 0.5), isNot(const VaSynth()));
    });
  });
}
