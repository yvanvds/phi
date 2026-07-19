import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/synth/va_oscillator.dart';
import 'package:phi/domain/synth/va_waveform.dart';

void main() {
  group('VaOscillator', () {
    test('round-trips through JSON across every waveform', () {
      for (final wave in VaWaveform.values) {
        final osc = VaOscillator(
          wave: wave,
          detune: -7.0,
          level: 0.75,
          pulseWidth: 0.3,
        );
        expect(VaOscillator.fromJson(osc.toJson()), osc);
      }
    });

    test('toJson serialises the waveform by name', () {
      expect(
        const VaOscillator(wave: VaWaveform.pulse).toJson()['wave'],
        'pulse',
      );
    });

    test('fromJson defaults an unknown waveform back to saw', () {
      final osc = VaOscillator.fromJson(const {'wave': 'moog'});
      expect(osc.wave, VaWaveform.saw);
    });

    test('fromJson fills defaults for a partial map', () {
      expect(VaOscillator.fromJson(const {}), const VaOscillator());
    });

    test('copyWith replaces only the given fields', () {
      const osc = VaOscillator();
      expect(osc.copyWith(level: 0.5).level, 0.5);
      expect(osc.copyWith(level: 0.5).wave, VaWaveform.saw);
    });

    test('equality is by value', () {
      expect(const VaOscillator(), const VaOscillator());
      expect(
        const VaOscillator(wave: VaWaveform.sine),
        isNot(const VaOscillator()),
      );
    });
  });
}
