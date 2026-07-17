import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_kind.dart';
import 'package:phi/domain/midi/parameter_event.dart';
import 'package:phi/domain/midi/transforms/velocity_curve.dart';
import 'package:phi/domain/midi/transforms/velocity_curve_shape.dart';
import 'package:phi/domain/midi/transforms/velocity_to_parameter_transform.dart';

void main() {
  group('VelocityToParameterTransform', () {
    // Linear 200 → 8200: value = 200 + velocity * 8000.
    const t = VelocityToParameterTransform(
      parameter: 'filter.cutoff',
      curve: VelocityCurve(valueAt0: 200, valueAt1: 8200),
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
      expect(off.curve, t.curve);
      expect(off.label, t.label);
    });

    test('copyWith reshapes the curve in place, keeping toggle and name', () {
      final steeper = t.copyWith(
        curve: const VelocityCurve(
          shape: VelocityCurveShape.exponential,
          valueAt0: 0,
          valueAt1: 100,
        ),
      );

      // A soft note now maps low on the ease-in curve, the accent stays high.
      expect(
        steeper
            .eventsFor(const [
              MidiNote(pitch: 60, start: 0, duration: 1, velocity: 0.5),
            ])
            .single
            .value,
        25,
      ); // 0.5² * 100
      // Toggle and label survive the reshape.
      expect(steeper.active, t.active);
      expect(steeper.label, t.label);
    });

    test('copyWith retargets the parameter path', () {
      final retargeted = t.copyWith(parameter: 'fm.index');

      expect(retargeted.parameter, 'fm.index');
      expect(retargeted.curve, t.curve);
      expect(
        retargeted
            .eventsFor(const [
              MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1),
            ])
            .single
            .parameter,
        'fm.index',
      );
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
