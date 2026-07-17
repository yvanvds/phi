import '../midi_note.dart';

/// One scalar field of a [MidiNote] a note predicate can test (issue #109).
///
/// A [NoteFieldCondition] pairs a field with a comparison and a threshold, so
/// the field has to expose the note's value as a single comparable [double].
/// [channel] widens to a double for a uniform seam — a channel is a whole
/// number, but comparing it as a double costs nothing and keeps every field on
/// one code path. The [label] is what the predicate editor's field picker shows.
enum NoteField {
  /// The note's (fractional) MIDI pitch — `60.0` is middle C.
  pitch('pitch'),

  /// The note's velocity, normalised to `[0, 1]`.
  velocity('velocity'),

  /// The note's voice channel (a whole number, read as a double here).
  channel('channel'),

  /// The note's start beat from the clip origin.
  start('start');

  const NoteField(this.label);

  /// Display label for the predicate editor's field picker.
  final String label;

  /// Reads this field off [note] as the comparable value a condition tests.
  double read(MidiNote note) => switch (this) {
    NoteField.pitch => note.pitch,
    NoteField.velocity => note.velocity,
    NoteField.channel => note.channel.toDouble(),
    NoteField.start => note.start,
  };
}
