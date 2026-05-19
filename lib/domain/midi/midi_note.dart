/// A single MIDI note inside a [MidiClip].
///
/// `start` and `duration` are measured in beats from the clip origin; the
/// host clip carries the meter that turns beats into seconds. `velocity` is
/// normalised to `[0, 1]` so transformations don't have to round-trip the
/// 7-bit MIDI range until output.
class MidiNote {
  const MidiNote({
    required this.pitch,
    required this.start,
    required this.duration,
    required this.velocity,
    this.channel = 0,
  });

  final int pitch;
  final double start;
  final double duration;
  final double velocity;
  final int channel;

  MidiNote copyWith({
    int? pitch,
    double? start,
    double? duration,
    double? velocity,
    int? channel,
  }) => MidiNote(
    pitch: pitch ?? this.pitch,
    start: start ?? this.start,
    duration: duration ?? this.duration,
    velocity: velocity ?? this.velocity,
    channel: channel ?? this.channel,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MidiNote &&
          other.pitch == pitch &&
          other.start == start &&
          other.duration == duration &&
          other.velocity == velocity &&
          other.channel == channel;

  @override
  int get hashCode => Object.hash(pitch, start, duration, velocity, channel);

  @override
  String toString() =>
      'MidiNote(p:$pitch t:$start d:$duration v:$velocity c:$channel)';
}
