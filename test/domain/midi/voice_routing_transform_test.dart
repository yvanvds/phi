import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_kind.dart';
import 'package:phi/domain/midi/music_scale.dart';
import 'package:phi/domain/midi/transforms/voice_routing_rule.dart';
import 'package:phi/domain/midi/transforms/voice_routing_transform.dart';

MidiNote _note({double pitch = 60, double velocity = 0.7, int channel = 0}) =>
    MidiNote(
      pitch: pitch,
      start: 0,
      duration: 1,
      velocity: velocity,
      channel: channel,
    );

void main() {
  group('PitchRangeRule', () {
    const rule = PitchRangeRule(minPitch: 48, maxPitch: 60, channel: 2);

    test('matches inside the range, bounds inclusive', () {
      expect(rule.matches(_note(pitch: 48)), isTrue);
      expect(rule.matches(_note(pitch: 54)), isTrue);
      expect(rule.matches(_note(pitch: 60)), isTrue);
    });

    test('rejects outside the range', () {
      expect(rule.matches(_note(pitch: 47)), isFalse);
      expect(rule.matches(_note(pitch: 61)), isFalse);
    });
  });

  group('VelocityRangeRule', () {
    const rule = VelocityRangeRule(
      minVelocity: 0.5,
      maxVelocity: 0.8,
      channel: 3,
    );

    test('matches inside the range, bounds inclusive', () {
      expect(rule.matches(_note(velocity: 0.5)), isTrue);
      expect(rule.matches(_note(velocity: 0.65)), isTrue);
      expect(rule.matches(_note(velocity: 0.8)), isTrue);
    });

    test('rejects outside the range', () {
      expect(rule.matches(_note(velocity: 0.49)), isFalse);
      expect(rule.matches(_note(velocity: 0.81)), isFalse);
    });
  });

  group('ScaleDegreeRule', () {
    // D dorian on tonic 62: degrees 1..7 = D E F G A B C.
    const rule = ScaleDegreeRule(
      scale: MusicScale.dorian,
      tonic: 62,
      degrees: {1, 5},
      channel: 4,
    );

    test('matches the tonic and dominant in any octave', () {
      expect(rule.matches(_note(pitch: 62)), isTrue); // D4, degree 1
      expect(rule.matches(_note(pitch: 69)), isTrue); // A4, degree 5
      expect(rule.matches(_note(pitch: 50)), isTrue); // D3, degree 1
      expect(rule.matches(_note(pitch: 81)), isTrue); // A5, degree 5
    });

    test('rejects other scale degrees', () {
      expect(rule.matches(_note(pitch: 64)), isFalse); // E, degree 2
      expect(rule.matches(_note(pitch: 72)), isFalse); // C, degree 7
    });

    test('rejects pitches outside the scale entirely', () {
      expect(rule.matches(_note(pitch: 63)), isFalse); // Eb, not in D dorian
    });
  });

  group('VoiceRoutingTransform', () {
    test('is a voice-family transform', () {
      const t = VoiceRoutingTransform(rules: [], label: 'route');
      expect(t.kind, MidiTransformKind.voice);
    });

    test('assigns the channel of the first matching rule', () {
      const t = VoiceRoutingTransform(
        rules: [
          PitchRangeRule(minPitch: 0, maxPitch: 59, channel: 1),
          PitchRangeRule(minPitch: 60, maxPitch: 127, channel: 2),
        ],
        label: 'split @ 60',
      );

      final out = t.apply([_note(pitch: 50), _note(pitch: 70)]);

      expect(out[0].channel, 1);
      expect(out[1].channel, 2);
    });

    test('first match wins when rules overlap', () {
      const t = VoiceRoutingTransform(
        rules: [
          VelocityRangeRule(minVelocity: 0.9, maxVelocity: 1.0, channel: 5),
          PitchRangeRule(minPitch: 0, maxPitch: 127, channel: 1),
        ],
        label: 'accents first',
      );

      final out = t.apply([
        _note(pitch: 60, velocity: 0.95),
        _note(pitch: 60, velocity: 0.4),
      ]);

      expect(out[0].channel, 5); // accent rule takes it before the catch-all
      expect(out[1].channel, 1);
    });

    test('a note no rule matches keeps its incoming channel', () {
      const t = VoiceRoutingTransform(
        rules: [PitchRangeRule(minPitch: 100, maxPitch: 127, channel: 9)],
        label: 'high only',
      );

      final out = t.apply([_note(pitch: 60, channel: 3)]);

      expect(out.single.channel, 3);
    });

    test('routing changes only the channel', () {
      const t = VoiceRoutingTransform(
        rules: [PitchRangeRule(minPitch: 0, maxPitch: 127, channel: 7)],
        label: 'all',
      );
      final source = _note(pitch: 64, velocity: 0.6);

      final out = t.apply([source]).single;

      expect(out, source.copyWith(channel: 7));
    });

    test('copyWith toggles active and keeps the rules', () {
      const t = VoiceRoutingTransform(
        rules: [PitchRangeRule(minPitch: 0, maxPitch: 127, channel: 1)],
        label: 'route',
      );

      final off = t.copyWith(active: false);

      expect(off.active, isFalse);
      expect(off.label, t.label);
      expect(off.rules, same(t.rules));
    });
  });
}
