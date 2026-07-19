import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/synth/fm_operator.dart';
import 'package:phi/domain/synth/fm_synth.dart';
import 'package:phi/domain/synth/synth_kind.dart';

void main() {
  group('FmSynth', () {
    test('is of kind fm', () {
      expect(const FmSynth().kind, SynthKind.fm);
    });

    test('round-trips a bank + patch with overrides', () {
      const synth = FmSynth(
        bankAsset: 'assets/rhodes.syx',
        patchIndex: 12,
        algorithm: 5,
        feedback: 4,
        transpose: -12,
        operators: [
          FmOperator(op: 0, outputLevel: 90),
          FmOperator(op: 5, enabled: false),
        ],
        voiceCount: 8,
      );
      expect(FmSynth.fromJson(synth.toJson()), synth);
    });

    test('round-trips the built-in patch with no overrides', () {
      const synth = FmSynth();
      expect(FmSynth.fromJson(synth.toJson()), synth);
    });

    test('toJson omits null overrides and the absent bank', () {
      expect(const FmSynth(patchIndex: 2).toJson(), {
        'kind': 'fm',
        'patchIndex': 2,
        'operators': <Object?>[],
        'voiceCount': 8,
      });
    });

    test('toJson includes overrides when pinned', () {
      final json = const FmSynth(bankAsset: 'a.syx', algorithm: 3).toJson();
      expect(json['bankAsset'], 'a.syx');
      expect(json['algorithm'], 3);
    });

    test('fromJson defaults missing keys and leaves overrides absent', () {
      final synth = FmSynth.fromJson(const {'kind': 'fm'});
      expect(synth, const FmSynth());
      expect(synth.algorithm, isNull);
      expect(synth.operators, isEmpty);
    });

    test('equality reaches into the operator list', () {
      expect(const FmSynth(), const FmSynth());
      expect(
        const FmSynth(operators: [FmOperator(op: 0)]),
        isNot(const FmSynth()),
      );
      expect(const FmSynth(algorithm: 1), isNot(const FmSynth()));
    });
  });
}
