/// One flattened, beat-timed note the engine clip transport dispatches.
///
/// The Phi-side counterpart of `package:yse`'s `ClipEvent`: the interpretation
/// layer (`EngineMidiController`) resolves each `MidiNote` — rounding the
/// fractional pitch to its nearest semitone and, in microtonal mode, splitting
/// off the leftover cents as [pitchBend] — into this immutable, wire-ready
/// shape and pushes a whole list to a [MidiTransport]. The engine then owns
/// *when* every event fires, so playback no longer rides the UI isolate's
/// timer (issue #101).
///
/// Channels stay in Phi's `0..15` convention here; the real transport maps
/// them onto the engine's `1..16` at the FFI boundary, keeping the wire detail
/// out of the interpretation layer.
class TransportNote {
  const TransportNote({
    required this.startBeat,
    required this.durationBeats,
    required this.channel,
    required this.pitch,
    required this.velocity,
    this.pitchBend = 0.0,
  });

  /// Beat within the loop at which the note starts (`>= 0`).
  final double startBeat;

  /// Note length in beats.
  final double durationBeats;

  /// MIDI channel in Phi's `0..15` convention.
  final int channel;

  /// The integer MIDI note the fractional pitch resolved to (`0..127`).
  final int pitch;

  /// Velocity normalised to `[0, 1]`.
  final double velocity;

  /// Per-note pitch bend in `[-1, 1]` for microtonal voicing; `0` bends
  /// nothing. `+1` / `-1` map to the assumed ±2-semitone bend range.
  final double pitchBend;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransportNote &&
          other.startBeat == startBeat &&
          other.durationBeats == durationBeats &&
          other.channel == channel &&
          other.pitch == pitch &&
          other.velocity == velocity &&
          other.pitchBend == pitchBend;

  @override
  int get hashCode => Object.hash(
    startBeat,
    durationBeats,
    channel,
    pitch,
    velocity,
    pitchBend,
  );

  @override
  String toString() =>
      'TransportNote(start:$startBeat dur:$durationBeats ch:$channel '
      'pitch:$pitch vel:$velocity bend:$pitchBend)';
}
