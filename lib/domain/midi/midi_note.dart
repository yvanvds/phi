/// A single MIDI note inside a [MidiClip].
///
/// `start` and `duration` are measured in beats from the clip origin; the
/// host clip carries the meter that turns beats into seconds. `velocity` is
/// normalised to `[0, 1]` so transformations don't have to round-trip the
/// 7-bit MIDI range until output.
///
/// [pitch] is a **fractional** MIDI note number (issue #36): `60.0` is middle
/// C, `60.5` sits a quarter-tone above it, `60.5` again a hair under C♯. This
/// lets a clip carry microtonal / just-intonation / arbitrary-cents tunings
/// through the transform chain; the output stage rounds to the nearest
/// semitone and (optionally) voices the leftover cents as pitch-bend. Whole
/// numbers behave exactly like the old `int` pitch.
///
/// [voice] is the note's **`voice.` registry address** in dotted string form
/// (`voice.bass`), the keystone binding note → sound → bus (design
/// `docs/design/racks-and-voices.md` §3, §6). A [VoiceRoutingTransform] assigns
/// it, a [SplittingTransform] layer may carry it, and at flatten time the
/// session maps it to the voice's allocated engine channel. `null` is an
/// **unrouted** note: it resolves to the seeded default voice (`voice.default`).
/// The address is stored as a plain string so a `MidiNote` stays `const`-able
/// and its persistence/journal stays a bare JSON scalar.
class MidiNote {
  const MidiNote({
    required this.pitch,
    required this.start,
    required this.duration,
    required this.velocity,
    this.voice,
  });

  final double pitch;
  final double start;
  final double duration;
  final double velocity;

  /// The `voice.` address this note routes to, or `null` when unrouted (it then
  /// resolves to the seeded default voice at flatten).
  final String? voice;

  MidiNote copyWith({
    double? pitch,
    double? start,
    double? duration,
    double? velocity,
    String? voice,
  }) => MidiNote(
    pitch: pitch ?? this.pitch,
    start: start ?? this.start,
    duration: duration ?? this.duration,
    velocity: velocity ?? this.velocity,
    voice: voice ?? this.voice,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MidiNote &&
          other.pitch == pitch &&
          other.start == start &&
          other.duration == duration &&
          other.velocity == velocity &&
          other.voice == voice;

  @override
  int get hashCode => Object.hash(pitch, start, duration, velocity, voice);

  @override
  String toString() =>
      'MidiNote(p:$pitch t:$start d:$duration v:$velocity voice:$voice)';
}
