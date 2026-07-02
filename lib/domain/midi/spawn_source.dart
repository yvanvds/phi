import 'midi_note.dart';

/// Which scalar of a [MidiNote] a spawn axis reads.
///
/// The four note dimensions an agent's position (or voice) can bind to — the
/// vision's "position derives from pitch/time/velocity/channel" (§3.7). Each
/// case knows how to pull its raw scalar off a note; a [SpawnAxis] then remaps
/// that raw value into a spatial coordinate.
enum SpawnSource {
  /// Fractional MIDI pitch (`MidiNote.pitch`).
  pitch,

  /// Start position in beats from the clip origin (`MidiNote.start`).
  time,

  /// Normalised velocity in `[0, 1]` (`MidiNote.velocity`).
  velocity,

  /// Voice channel (`MidiNote.channel`).
  channel;

  /// The raw scalar this source reads off [note], before any axis remapping.
  double valueOf(MidiNote note) => switch (this) {
    SpawnSource.pitch => note.pitch,
    SpawnSource.time => note.start,
    SpawnSource.velocity => note.velocity,
    SpawnSource.channel => note.channel.toDouble(),
  };
}
