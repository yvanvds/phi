import 'click_beat.dart';

/// A one-bar metronome click pattern (design `docs/design/midi-recording.md`
/// §4).
///
/// Pure, immutable domain value: a meter ([beatsPerBar]) and whether the
/// downbeat is accented ([accentDownbeat]). [beats] generates the bar's clicks —
/// one [ClickBeat] per beat, the first accented when [accentDownbeat] is set.
/// The pattern loops on the chosen time domain's clock, so this carries no
/// tempo, no notes and no engine wiring — the metronome controller maps each
/// beat onto a sounding click and paces the loop from the domain's tempo.
class ClickPattern {
  /// Build a pattern for [beatsPerBar] beats (clamped to at least one — a bar
  /// always has a downbeat), accenting the downbeat when [accentDownbeat].
  ClickPattern({required int beatsPerBar, this.accentDownbeat = true})
    : beatsPerBar = beatsPerBar < 1 ? 1 : beatsPerBar;

  /// Beats per bar — the meter numerator. Always at least one.
  final int beatsPerBar;

  /// Whether the downbeat (beat `0`) is accented. When false every beat is an
  /// equal, unaccented click.
  final bool accentDownbeat;

  /// The bar's clicks in beat order: one [ClickBeat] per beat, beat `0` carrying
  /// the [accent] exactly when [accentDownbeat]. A 4/4 accented bar is
  /// `[accent, plain, plain, plain]`; the same bar with the accent off is four
  /// equal clicks.
  List<ClickBeat> beats() => [
    for (var i = 0; i < beatsPerBar; i++)
      ClickBeat(beat: i, accent: accentDownbeat && i == 0),
  ];

  ClickPattern copyWith({int? beatsPerBar, bool? accentDownbeat}) =>
      ClickPattern(
        beatsPerBar: beatsPerBar ?? this.beatsPerBar,
        accentDownbeat: accentDownbeat ?? this.accentDownbeat,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClickPattern &&
          other.beatsPerBar == beatsPerBar &&
          other.accentDownbeat == accentDownbeat;

  @override
  int get hashCode => Object.hash(beatsPerBar, accentDownbeat);

  @override
  String toString() =>
      'ClickPattern(beatsPerBar: $beatsPerBar, accentDownbeat: $accentDownbeat)';
}
