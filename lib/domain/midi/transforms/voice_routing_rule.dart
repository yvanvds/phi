import '../midi_note.dart';
import '../music_scale.dart';

/// One routing predicate inside a [VoiceRoutingTransform]: "if the note
/// matches, send it to [voice]".
///
/// A sealed family rather than a single struct-of-nullables so each rule
/// spells out exactly the fields it needs — a scale-degree rule can't be
/// half-configured, and adding a new criterion later is a new subclass
/// rather than another nullable on everything.
sealed class VoiceRoutingRule {
  const VoiceRoutingRule({required this.voice});

  /// The [MidiNote.voice] address assigned when this rule matches. At flatten
  /// time the session maps that voice onto its allocated engine channel (design
  /// `docs/design/racks-and-voices.md` §6).
  final String voice;

  bool matches(MidiNote note);
}

/// Matches notes whose pitch lies in `[minPitch, maxPitch]` (inclusive) —
/// the classic keyboard split: bass below the split point to one voice,
/// lead above it to another.
final class PitchRangeRule extends VoiceRoutingRule {
  const PitchRangeRule({
    required this.minPitch,
    required this.maxPitch,
    required super.voice,
  });

  final int minPitch;
  final int maxPitch;

  @override
  bool matches(MidiNote note) =>
      note.pitch >= minPitch && note.pitch <= maxPitch;
}

/// Matches notes whose velocity lies in `[minVelocity, maxVelocity]`
/// (inclusive, normalised to `[0, 1]` like [MidiNote.velocity]) — soft
/// notes to a pad voice, accents to a percussive one.
final class VelocityRangeRule extends VoiceRoutingRule {
  const VelocityRangeRule({
    required this.minVelocity,
    required this.maxVelocity,
    required super.voice,
  });

  final double minVelocity;
  final double maxVelocity;

  @override
  bool matches(MidiNote note) =>
      note.velocity >= minVelocity && note.velocity <= maxVelocity;
}

/// Matches notes sitting on the given [degrees] of a [scale] — e.g. route
/// every tonic and dominant (degrees `{1, 5}`) to a drone voice.
///
/// Degrees are **1-based** to match musical convention: degree 1 is the
/// tonic, degree 5 the dominant. A note whose pitch class is not in the
/// scale at all never matches, whatever [degrees] says.
final class ScaleDegreeRule extends VoiceRoutingRule {
  const ScaleDegreeRule({
    required this.scale,
    required this.tonic,
    required this.degrees,
    required super.voice,
  });

  final MusicScale scale;
  final int tonic;
  final Set<int> degrees;

  @override
  bool matches(MidiNote note) {
    // Scale-degree membership is a 12-TET notion; a microtonal note routes by
    // its nearest semitone.
    final pc = ((note.pitch.round() - tonic) % 12 + 12) % 12;
    final index = scale.intervals.indexOf(pc);
    return index >= 0 && degrees.contains(index + 1);
  }
}
