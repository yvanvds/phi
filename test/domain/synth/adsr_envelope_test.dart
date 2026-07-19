import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/synth/adsr_envelope.dart';

void main() {
  group('AdsrEnvelope', () {
    test('round-trips through JSON', () {
      const env = AdsrEnvelope(
        attack: 0.05,
        decay: 0.3,
        sustain: 0.6,
        release: 1.2,
      );
      expect(AdsrEnvelope.fromJson(env.toJson()), env);
    });

    test('toJson emits every stage in a stable order', () {
      expect(
        const AdsrEnvelope(
          attack: 0.05,
          decay: 0.3,
          sustain: 0.6,
          release: 1.2,
        ).toJson(),
        {'attack': 0.05, 'decay': 0.3, 'sustain': 0.6, 'release': 1.2},
      );
    });

    test('fromJson fills defaults for a partial map', () {
      const env = AdsrEnvelope();
      final decoded = AdsrEnvelope.fromJson(const {});
      expect(decoded, env);
    });

    test('copyWith replaces only the given fields', () {
      const env = AdsrEnvelope();
      expect(env.copyWith(sustain: 0.2).sustain, 0.2);
      expect(env.copyWith(sustain: 0.2).attack, env.attack);
    });

    test('equality and hashCode are by value', () {
      expect(const AdsrEnvelope(), const AdsrEnvelope());
      expect(const AdsrEnvelope().hashCode, const AdsrEnvelope().hashCode);
      expect(const AdsrEnvelope(attack: 0.5), isNot(const AdsrEnvelope()));
    });
  });
}
