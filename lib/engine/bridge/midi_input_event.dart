/// A parsed MIDI **input** note event delivered on [MidiGateway.inputEvents]
/// (design `docs/design/racks-and-voices.md` §7).
///
/// The gateway decodes the bridge's raw `MidiInParsedMessage` (status nibble +
/// channel + two data bytes) into this yse-free value type so the racks/voice
/// layer can arm a voice and audition it without touching `package:yse`. Only
/// **note** messages surface here — the arm/audition use case the design calls
/// for; every other channel-voice message (CC, pitch-bend, …) is filtered out
/// (it still pulses [MidiGateway.inputActivity], which is unchanged).
///
/// A running-status note-on with velocity `0` is the conventional note-off, so
/// [fromParsed] normalises it to a [MidiInputEventType.noteOff]. Nothing routes
/// these events anywhere yet — this issue only exposes the stream, exactly as
/// the settings epic exposed the activity tick before anything consumed it
/// (design §7); arming and audition are the racks-surface issues (#211).
class MidiInputEvent {
  /// Builds a note event directly. Prefer [fromParsed] when decoding a wire
  /// message; this constructor exists for the fake gateway and tests.
  const MidiInputEvent({
    required this.type,
    required this.note,
    required this.velocity,
    required this.channel,
    required this.port,
    this.timestamp = 0,
  });

  /// Decode a parsed wire message into a [MidiInputEvent], or `null` when it is
  /// not a note message (so the caller emits nothing on the note stream).
  ///
  /// [status] is the high status nibble (`0x80`..`0xF0`) and [wireChannel] the
  /// low nibble (`0`..`15`) exactly as `MidiInParsedMessage` carries them;
  /// [data1] is the note number and [data2] the velocity. The reported
  /// [channel] is **1-based** (`1`..`16`) to match the engine voice-channel
  /// space (design §3) — the bridge adds one to the zero-based wire nibble.
  static MidiInputEvent? fromParsed({
    required int status,
    required int wireChannel,
    required int data1,
    required int data2,
    required String port,
    double timestamp = 0,
  }) {
    const noteOnStatus = 0x90;
    const noteOffStatus = 0x80;
    final MidiInputEventType type;
    if (status == noteOnStatus) {
      // Velocity 0 on a note-on is the running-status note-off.
      type = data2 == 0
          ? MidiInputEventType.noteOff
          : MidiInputEventType.noteOn;
    } else if (status == noteOffStatus) {
      type = MidiInputEventType.noteOff;
    } else {
      return null; // Not a note message — nothing on the note stream.
    }
    return MidiInputEvent(
      type: type,
      note: data1,
      velocity: data2,
      channel: wireChannel + 1,
      port: port,
      timestamp: timestamp,
    );
  }

  /// Whether this is a note-on or a note-off.
  final MidiInputEventType type;

  /// The MIDI note number (`0`..`127`).
  final int note;

  /// The note velocity (`0`..`127`). A note-off carries its release velocity,
  /// or `0` for a velocity-0 note-on normalised to a note-off.
  final int velocity;

  /// The 1-based MIDI channel (`1`..`16`) — aligned with the engine
  /// voice-channel space (design §3), not the zero-based wire nibble.
  final int channel;

  /// The name of the input port the message arrived on — the same port name
  /// [MidiGateway.inputActivity] emits, so a consumer can scope by device.
  final String port;

  /// The RtMidi timestamp in seconds, passed through from the wire message.
  final double timestamp;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MidiInputEvent &&
          other.type == type &&
          other.note == note &&
          other.velocity == velocity &&
          other.channel == channel &&
          other.port == port &&
          other.timestamp == timestamp;

  @override
  int get hashCode =>
      Object.hash(type, note, velocity, channel, port, timestamp);

  @override
  String toString() =>
      'MidiInputEvent(${type.name}, note: $note, velocity: $velocity, '
      'channel: $channel, port: $port)';
}

/// Whether a [MidiInputEvent] starts or stops a note.
enum MidiInputEventType {
  /// A note-on with non-zero velocity.
  noteOn,

  /// A note-off, or a note-on whose velocity was `0`.
  noteOff,
}
