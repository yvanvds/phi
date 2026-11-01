import '../midi/midi_pitch.dart';

/// One key's outline inside a keyboard, as fractions of the keyboard's width
/// ([left], [right]) and height ([bottom]; a key always starts at the top).
typedef KeyBounds = ({double left, double right, double bottom});

/// The geometry of a `.kslider` keyboard showing pitches [low] to [high]
/// (issue #473): where each key is, which key a point lands on, and the
/// velocity a press at that depth plays.
///
/// Everything is in fractions of the keyboard's size (0–1 across, 0–1 down),
/// so the painter and the gesture share one layout whatever the box measures.
/// White keys share the width equally; a black key is [blackWidth] of a white
/// one, centred on the seam it sits over, and reaches [blackDepth] down.
///
/// The visible range is decoration (a GUI property), not engine state: the
/// object always holds all 128 keys. [low] and [high] are widened to white
/// keys, so the keyboard never starts or ends on half a black key.
class KeyboardLayout {
  /// A keyboard from [from] to [to], in either order, clamped to MIDI and
  /// widened outwards to white keys.
  factory KeyboardLayout(int from, int to) {
    var low = (from < to ? from : to).clamp(0, MidiPitch.max);
    var high = (from < to ? to : from).clamp(0, MidiPitch.max);
    // Every black key has a white neighbour on both sides inside 0–127.
    if (MidiPitch.isBlack(low)) low--;
    if (MidiPitch.isBlack(high)) high++;
    return KeyboardLayout._(low, high);
  }

  /// Read the range from the stored GUI properties [low] and [high]; an absent
  /// or unparseable one keeps its default.
  factory KeyboardLayout.fromGui(String low, String high) => KeyboardLayout(
    int.tryParse(low.trim()) ?? defaultLow,
    int.tryParse(high.trim()) ?? defaultHigh,
  );

  KeyboardLayout._(this.low, this.high)
    : whiteCount = _whitesBelow(low, high + 1);

  /// The range a keyboard shows when its GUI properties name none: C3–C6,
  /// three octaves around middle C.
  static const int defaultLow = 48;
  static const int defaultHigh = 84;

  /// The narrowest span [movedLow] / [movedHigh] leave, in semitones: an
  /// octave's twelve keys, C up to B.
  static const int minSpan = 11;

  /// A black key's width, as a fraction of a white key's.
  static const double blackWidth = 0.6;

  /// How far down a black key reaches, as a fraction of the keyboard's height.
  static const double blackDepth = 0.6;

  /// The lowest pitch shown — always a white key.
  final int low;

  /// The highest pitch shown — always a white key.
  final int high;

  /// How many white keys the keyboard has.
  final int whiteCount;

  /// Every pitch shown, low to high.
  Iterable<int> get pitches sync* {
    for (var p = low; p <= high; p++) {
      yield p;
    }
  }

  /// Whether this is the range a keyboard shows when nothing names one.
  bool get isDefault => low == defaultLow && high == defaultHigh;

  /// This keyboard moved [octaves] up (or down, negative) whole, or null when
  /// that would run off MIDI's 0–127 (issue #515). Whole octaves keep both ends
  /// on white keys.
  KeyboardLayout? shifted(int octaves) =>
      _within(low + 12 * octaves, high + 12 * octaves);

  /// This keyboard with its bottom end moved [octaves] (down widens it, up
  /// narrows it), or null off MIDI or narrower than [minSpan].
  KeyboardLayout? movedLow(int octaves) => _within(low + 12 * octaves, high);

  /// This keyboard with its top end moved [octaves] (up widens it, down
  /// narrows it), or null off MIDI or narrower than [minSpan].
  KeyboardLayout? movedHigh(int octaves) => _within(low, high + 12 * octaves);

  static KeyboardLayout? _within(int low, int high) {
    if (low < 0 || high > MidiPitch.max || high - low < minSpan) return null;
    return KeyboardLayout(low, high);
  }

  /// Whether [pitch] is on this keyboard.
  bool shows(int pitch) => pitch >= low && pitch <= high;

  /// The white keys in `[from, to)`.
  static int _whitesBelow(int from, int to) {
    var n = 0;
    for (var p = from; p < to; p++) {
      if (!MidiPitch.isBlack(p)) n++;
    }
    return n;
  }

  /// Where [pitch]'s key is drawn. [pitch] must be one [shows] accepts.
  KeyBounds boundsOf(int pitch) {
    final white = 1 / whiteCount;
    final seam = _whitesBelow(low, pitch) * white;
    if (!MidiPitch.isBlack(pitch)) {
      return (left: seam, right: seam + white, bottom: 1);
    }
    final half = white * blackWidth / 2;
    return (left: seam - half, right: seam + half, bottom: blackDepth);
  }

  /// The key under the point ([x], [y]) in fractions of the keyboard, or null
  /// off it. A black key wins over the white keys it overlaps.
  int? keyAt(double x, double y) {
    if (!(x >= 0 && x <= 1 && y >= 0 && y <= 1)) return null;
    if (y <= blackDepth) {
      for (var p = low; p <= high; p++) {
        if (!MidiPitch.isBlack(p)) continue;
        final b = boundsOf(p);
        if (x >= b.left && x < b.right) return p;
      }
    }
    final index = (x * whiteCount).floor().clamp(0, whiteCount - 1);
    var seen = -1;
    for (var p = low; p <= high; p++) {
      if (MidiPitch.isBlack(p)) continue;
      if (++seen == index) return p;
    }
    return high;
  }

  /// The velocity a press [y] down the keyboard plays on [pitch]: 1 at the top
  /// of the key, rising to [MidiPitch.maxVelocity] at its bottom — so lower
  /// down is louder, on a black key as on a white one.
  int velocityAt(int pitch, double y) {
    final depth = (y / boundsOf(pitch).bottom).clamp(0.0, 1.0);
    return 1 + (depth * (MidiPitch.maxVelocity - 1)).round();
  }
}
