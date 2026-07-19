import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/voice/voice_definition.dart';
import 'package:phi/domain/voice/voice_kind.dart';

void main() {
  EntityAddress synth(String leaf) => EntityAddress.parse('synth.$leaf');
  EntityAddress mix(String leaf) => EntityAddress.parse('mix.$leaf');

  group('VoiceDefinition — internal', () {
    final bells = VoiceDefinition.internal(
      synth: synth('fm_bells'),
      output: mix('perc'),
      color: 'amber',
    );

    test('is internal and binds a synth', () {
      expect(bells.kind, VoiceKind.internal);
      expect(bells.synth, synth('fm_bells'));
      expect(bells.channel, isNull);
    });

    test('round-trips through JSON', () {
      expect(VoiceDefinition.fromJson(bells.toJson()), bells);
    });

    test('toJson carries synth + output + color, no channel', () {
      expect(bells.toJson(), {
        'kind': 'internal',
        'synth': 'synth.fm_bells',
        'output': 'mix.perc',
        'color': 'amber',
      });
    });

    test('references are the synth and the output bus', () {
      expect(bells.references, {synth('fm_bells'), mix('perc')});
    });

    test('withReferenceUpdated repoints the synth', () {
      final moved = bells.withReferenceUpdated(
        synth('fm_bells'),
        synth('fm_bells_v2'),
      );
      expect(moved.synth, synth('fm_bells_v2'));
      expect(moved.output, mix('perc'));
      expect(moved.references, {synth('fm_bells_v2'), mix('perc')});
    });

    test('withReferenceUpdated repoints the output bus', () {
      final moved = bells.withReferenceUpdated(mix('perc'), mix('drums'));
      expect(moved.output, mix('drums'));
      expect(moved.synth, synth('fm_bells'));
    });

    test('applying the inverse rewrite restores the original (undo)', () {
      final there = bells.withReferenceUpdated(mix('perc'), mix('drums'));
      final back = there.withReferenceUpdated(mix('drums'), mix('perc'));
      expect(back, bells);
    });

    test('copyWith re-points the synth while staying internal', () {
      final repointed = bells.copyWith(synth: synth('va_lead'));
      expect(repointed.synth, synth('va_lead'));
      expect(repointed.kind, VoiceKind.internal);
    });

    test('defaults its color to the first quick-pick swatch', () {
      final v = VoiceDefinition.internal(synth: synth('s'), output: mix('m'));
      expect(v.color, VoiceDefinition.defaultColor);
    });
  });

  group('VoiceDefinition — external', () {
    final bass = VoiceDefinition.external(
      channel: 3,
      output: mix('master'),
      color: 'voice2',
    );

    test('is external and carries a MIDI channel', () {
      expect(bass.kind, VoiceKind.external);
      expect(bass.channel, 3);
      expect(bass.synth, isNull);
    });

    test('round-trips through JSON', () {
      expect(VoiceDefinition.fromJson(bass.toJson()), bass);
    });

    test('toJson carries channel + output + color, no synth', () {
      expect(bass.toJson(), {
        'kind': 'external',
        'channel': 3,
        'output': 'mix.master',
        'color': 'voice2',
      });
    });

    test('references are only the output bus (no synth)', () {
      expect(bass.references, {mix('master')});
    });

    test('withReferenceUpdated repoints the output but never a channel', () {
      final moved = bass.withReferenceUpdated(mix('master'), mix('main'));
      expect(moved.output, mix('main'));
      expect(moved.channel, 3);
    });
  });

  group('VoiceDefinition.fromJson errors', () {
    test('a missing kind throws', () {
      expect(
        () => VoiceDefinition.fromJson(const {'output': 'mix.master'}),
        throwsFormatException,
      );
    });

    test('a missing output throws', () {
      expect(
        () => VoiceDefinition.fromJson(const {
          'kind': 'internal',
          'synth': 'synth.s',
        }),
        throwsFormatException,
      );
    });

    test('an internal voice with no synth throws', () {
      expect(
        () => VoiceDefinition.fromJson(const {
          'kind': 'internal',
          'output': 'mix.master',
        }),
        throwsFormatException,
      );
    });

    test('an external voice with no channel throws', () {
      expect(
        () => VoiceDefinition.fromJson(const {
          'kind': 'external',
          'output': 'mix.master',
        }),
        throwsFormatException,
      );
    });
  });
}
