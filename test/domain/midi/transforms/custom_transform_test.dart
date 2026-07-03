import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/custom_transform_definition.dart';
import 'package:phi/domain/midi/dsl_note.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_kind.dart';

List<DslNote> _octaveUp(List<DslNote> notes) =>
    notes.map((n) => n.copyWith(pitch: n.pitch + 12)).toList();

List<DslNote> _dropAll(List<DslNote> notes) => const [];

void main() {
  group('CustomTransform', () {
    const input = [
      MidiNote(pitch: 60, start: 0, duration: 1, velocity: 0.7, channel: 2),
      MidiNote(pitch: 64.5, start: 1, duration: 0.5, velocity: 0.5),
    ];

    test(
      'apply bridges MidiNote → DslNote → MidiNote through the function',
      () {
        final def = CustomTransformDefinition(
          name: 'octave up',
          kind: MidiTransformKind.pitch,
          transform: _octaveUp,
        );
        final out = def.instantiate().apply(input);

        expect(out.map((n) => n.pitch), [72, 76.5]);
        // Non-pitch fields survive the round-trip untouched.
        expect(out.first.channel, 2);
        expect(out.first.velocity, 0.7);
        expect(out[1].duration, 0.5);
      },
    );

    test('label and kind delegate to the definition', () {
      final def = CustomTransformDefinition(
        name: 'my transform',
        kind: MidiTransformKind.voice,
        transform: _octaveUp,
      );
      final t = def.instantiate();
      expect(t.label, 'my transform');
      expect(t.kind, MidiTransformKind.voice);
    });

    test('a note-dropping function yields an empty list', () {
      final def = CustomTransformDefinition(name: 'mute', transform: _dropAll);
      expect(def.instantiate().apply(input), isEmpty);
    });

    test('copyWith flips active while keeping the same definition', () {
      final def = CustomTransformDefinition(name: 'x', transform: _octaveUp);
      final t = def.instantiate();
      expect(t.active, isTrue);
      final off = t.copyWith(active: false);
      expect(off.active, isFalse);
      expect(off.definition, same(def));
    });

    test(
      'hot-reload: updating the definition changes an existing chip live',
      () {
        final def = CustomTransformDefinition(name: 'x', transform: _octaveUp);
        final t = def.instantiate();
        expect(t.apply(input).map((n) => n.pitch), [72, 76.5]);

        // Same CustomTransform instance, new behaviour — the reload path.
        def.updateTransform(
          (notes) => notes.map((n) => n.copyWith(pitch: 0)).toList(),
        );
        expect(t.apply(input).map((n) => n.pitch), [0, 0]);
      },
    );
  });
}
