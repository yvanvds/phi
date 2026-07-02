import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_kind.dart';
import 'package:phi/domain/midi/parameter_event.dart';
import 'package:phi/domain/midi/transforms/velocity_to_parameter_transform.dart';

double _cutoffCurve(double velocity) => 200 + velocity * 8000;

void main() {
  group('VelocityToParameterTransform', () {
    const t = VelocityToParameterTransform(
      parameter: 'filter.cutoff',
      curve: _cutoffCurve,
      label: 'v → cutoff',
    );

    test('is a voice-family transform', () {
      expect(t.kind, MidiTransformKind.voice);
    });

    test('apply passes notes through untouched', () {
      const notes = [
        MidiNote(pitch: 60, start: 0, duration: 1, velocity: 0.5),
        MidiNote(pitch: 64, start: 1, duration: 1, velocity: 0.9),
      ];

      expect(t.apply(notes), same(notes));
    });

    test('eventsFor emits one event per note through the curve', () {
      const notes = [
        MidiNote(pitch: 60, start: 0.0, duration: 1, velocity: 0.0),
        MidiNote(pitch: 64, start: 1.5, duration: 1, velocity: 0.5),
        MidiNote(pitch: 67, start: 3.0, duration: 1, velocity: 1.0),
      ];

      final events = t.eventsFor(notes);

      expect(events, const [
        ParameterEvent(parameter: 'filter.cutoff', beat: 0.0, value: 200),
        ParameterEvent(parameter: 'filter.cutoff', beat: 1.5, value: 4200),
        ParameterEvent(parameter: 'filter.cutoff', beat: 3.0, value: 8200),
      ]);
    });

    test('eventsFor on an empty list is empty', () {
      expect(t.eventsFor(const []), isEmpty);
    });

    test('copyWith toggles active and keeps parameter and curve', () {
      final off = t.copyWith(active: false);

      expect(off.active, isFalse);
      expect(off.parameter, 'filter.cutoff');
      expect(off.curve, same(t.curve));
      expect(off.label, t.label);
    });
  });

  group('ParameterEvent', () {
    test('equality is by value', () {
      const a = ParameterEvent(parameter: 'fm.index', beat: 1, value: 0.5);
      const b = ParameterEvent(parameter: 'fm.index', beat: 1, value: 0.5);
      const c = ParameterEvent(parameter: 'fm.index', beat: 2, value: 0.5);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
