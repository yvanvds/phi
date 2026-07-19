import '../midi_note.dart';

/// One scalar field of a [MidiNote] a note predicate can test (issue #109).
///
/// A [NoteFieldCondition] pairs a field with a comparison and a threshold, so
/// the field has to expose the note's value as a single comparable [double].
/// The note's **voice** is deliberately *not* a field: it is a `voice.` address,
/// not an orderable scalar, so it can't be compared against a threshold (the
/// channel-→-voice migration, design §6). The [label] is what the predicate
/// editor's field picker shows.
enum NoteField {
  /// The note's (fractional) MIDI pitch — `60.0` is middle C.
  pitch('pitch'),

  /// The note's velocity, normalised to `[0, 1]`.
  velocity('velocity'),

  /// The note's start beat from the clip origin.
  start('start');

  const NoteField(this.label);

  /// Display label for the predicate editor's field picker.
  final String label;

  /// Reads this field off [note] as the comparable value a condition tests.
  double read(MidiNote note) => switch (this) {
    NoteField.pitch => note.pitch,
    NoteField.velocity => note.velocity,
    NoteField.start => note.start,
  };
}
