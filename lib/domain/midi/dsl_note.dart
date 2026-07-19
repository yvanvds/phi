import 'midi_note.dart';

/// A single note as seen by a live-coded transform.
///
/// This is the **stable contract** the Code surface's DSL hands to a
/// performer-authored transform (issue #38) — deliberately decoupled from the
/// internal [MidiNote] so the domain model can evolve without breaking scripts
/// a performer has already written. It carries the same continuous fields plus
/// the [voice] address, all immutable: a transform receives a list of these,
/// returns a (possibly different) list of these, and Phi converts back to
/// [MidiNote]s at the chain boundary (see `CustomTransform`).
///
/// Fields mirror [MidiNote]: [pitch] is a fractional MIDI number (`60.0` is
/// middle C, `60.5` a quarter-tone above), [start] and [duration] are in
/// beats, [velocity] is normalised to `[0, 1]`, and [voice] is the note's
/// `voice.` address (or `null` when unrouted).
class DslNote {
  const DslNote({
    required this.pitch,
    required this.start,
    required this.duration,
    required this.velocity,
    this.voice,
  });

  /// Projects a domain [MidiNote] into the DSL contract.
  factory DslNote.fromNote(MidiNote note) => DslNote(
    pitch: note.pitch,
    start: note.start,
    duration: note.duration,
    velocity: note.velocity,
    voice: note.voice,
  );

  final double pitch;
  final double start;
  final double duration;
  final double velocity;

  /// The `voice.` address this note routes to, or `null` when unrouted.
  final String? voice;

  DslNote copyWith({
    double? pitch,
    double? start,
    double? duration,
    double? velocity,
    String? voice,
  }) => DslNote(
    pitch: pitch ?? this.pitch,
    start: start ?? this.start,
    duration: duration ?? this.duration,
    velocity: velocity ?? this.velocity,
    voice: voice ?? this.voice,
  );

  /// Materialises this DSL note back into a domain [MidiNote].
  MidiNote toNote() => MidiNote(
    pitch: pitch,
    start: start,
    duration: duration,
    velocity: velocity,
    voice: voice,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DslNote &&
          other.pitch == pitch &&
          other.start == start &&
          other.duration == duration &&
          other.velocity == velocity &&
          other.voice == voice;

  @override
  int get hashCode => Object.hash(pitch, start, duration, velocity, voice);

  @override
  String toString() =>
      'DslNote(p:$pitch t:$start d:$duration v:$velocity voice:$voice)';
}

/// A performer-authored transform in DSL terms: notes in, notes out.
///
/// This is the shape a live-coded `def my_transform(notes): ...` presents once
/// the Python kernel bridges it into Phi (issue #38 / #9). Today a plain Dart
/// callback stands behind it — the same "caller supplies the function" seam as
/// `NotePredicate`. Like every transform it must be pure — same input list, same
/// output list — so the chain stays memoisable.
typedef DslTransform = List<DslNote> Function(List<DslNote> notes);
