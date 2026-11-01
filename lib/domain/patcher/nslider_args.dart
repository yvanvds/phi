import '../midi/midi_pitch.dart';
import 'patch_args.dart';

/// An `.nslider`'s creation arguments, `minimum maximum spelling`
/// (issue #473), and the engine's rule for bounding a pitch by them.
class NsliderArgs {
  const NsliderArgs({
    required this.minimum,
    required this.maximum,
    required this.spelling,
  });

  /// Parse [args]. A missing or unparseable argument keeps its engine default:
  /// the whole MIDI range, spelled with sharps.
  factory NsliderArgs.parse(String args) {
    final parts = splitPatchArgs(args);
    int read(int i, int fallback) => i < parts.length
        ? num.tryParse(parts[i])?.truncate() ?? fallback
        : fallback;
    return NsliderArgs(
      minimum: read(0, 0),
      maximum: read(1, MidiPitch.max),
      spelling: read(2, 1),
    );
  }

  /// The `minimum` argument, as given.
  final int minimum;

  /// The `maximum` argument, as given.
  final int maximum;

  /// How a black key is spelled by default: 0 or above sharp, below 0 flat.
  final int spelling;

  /// The lower bound — the two bounds sorted and kept inside MIDI, as
  /// `gNSlider::Bound` reads them.
  int get low =>
      (minimum < maximum ? minimum : maximum).clamp(0, MidiPitch.max);

  /// The upper bound, likewise.
  int get high =>
      (minimum < maximum ? maximum : minimum).clamp(0, MidiPitch.max);

  /// [pitch] held inside [low]–[high].
  int bound(int pitch) => pitch.clamp(low, high);
}
