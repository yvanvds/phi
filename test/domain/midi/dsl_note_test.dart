import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/dsl_note.dart';
import 'package:phi/domain/midi/midi_note.dart';

void main() {
  group('DslNote', () {
    const note = MidiNote(
      pitch: 60.5,
      start: 1.25,
      duration: 0.5,
      velocity: 0.8,
      channel: 3,
    );

    test('fromNote / toNote round-trips every field', () {
      final dsl = DslNote.fromNote(note);
      expect(dsl.pitch, 60.5);
      expect(dsl.start, 1.25);
      expect(dsl.duration, 0.5);
      expect(dsl.velocity, 0.8);
      expect(dsl.channel, 3);
      expect(dsl.toNote(), note);
    });

    test('copyWith overrides only the named fields', () {
      final dsl = DslNote.fromNote(note);
      final up = dsl.copyWith(pitch: dsl.pitch + 12);
      expect(up.pitch, 72.5);
      expect(up.start, dsl.start);
      expect(up.duration, dsl.duration);
      expect(up.velocity, dsl.velocity);
      expect(up.channel, dsl.channel);
    });

    test('value equality and hashCode', () {
      expect(DslNote.fromNote(note), DslNote.fromNote(note));
      expect(DslNote.fromNote(note).hashCode, DslNote.fromNote(note).hashCode);
      expect(
        DslNote.fromNote(note),
        isNot(DslNote.fromNote(note).copyWith(channel: 4)),
      );
    });

    test('channel defaults to 0', () {
      const dsl = DslNote(pitch: 60, start: 0, duration: 1, velocity: 1);
      expect(dsl.channel, 0);
    });
  });
}
