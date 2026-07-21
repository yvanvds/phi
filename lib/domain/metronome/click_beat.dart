/// One beat of a metronome's one-bar click pattern (design
/// `docs/design/midi-recording.md` §4).
///
/// A pure value type: the zero-based [beat] index within the bar and whether it
/// carries the bar's downbeat [accent]. The engine's metronome maps each beat
/// onto a sounding click — an accented beat a higher, louder click — so this
/// stays free of any note / engine detail (domain-layer rule).
class ClickBeat {
  const ClickBeat({required this.beat, required this.accent});

  /// Zero-based position of this beat within the bar (`0` is the downbeat).
  final int beat;

  /// Whether this beat is the accented downbeat.
  final bool accent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClickBeat && other.beat == beat && other.accent == accent;

  @override
  int get hashCode => Object.hash(beat, accent);

  @override
  String toString() => 'ClickBeat(beat: $beat, accent: $accent)';
}
