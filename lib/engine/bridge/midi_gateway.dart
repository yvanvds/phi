/// Abstract port over `package:yse`'s MIDI **output** surface.
///
/// `EngineMidiController` depends on this interface, not on `package:yse`
/// directly, so tests can swap in a fake gateway and the production code is
/// the only place the real FFI surface is touched. Mirrors [YseGateway] for
/// the audio side. See `real_midi_gateway.dart` for the production
/// implementation and `test/.../fake_midi_gateway.dart` for the test double.
abstract interface class MidiGateway {
  /// Number of MIDI output devices visible to the engine. `0` when none are
  /// present or the platform has no MIDI support.
  int get outputDeviceCount;

  /// Name of the output device at [id]. Pair with [open].
  String outputDeviceName(int id);

  /// Open the output device at [port]. A second call closes the previous
  /// port and opens the new one. No-op for an out-of-range [port].
  void open(int port);

  /// Whether an output port is currently open.
  bool get isOpen;

  /// Send Note-On. [channel] is `0..15`, [pitch] and [velocity] are `0..127`.
  void noteOn({
    required int channel,
    required int pitch,
    required int velocity,
  });

  /// Send Note-Off. [channel] is `0..15`, [pitch] is `0..127`.
  void noteOff({required int channel, required int pitch});

  /// Send three raw MIDI bytes — the escape hatch for messages the typed
  /// helpers don't cover.
  void raw3(int a, int b, int c);

  /// Silence every sounding note. Pass a [channel] to scope it, or `null`
  /// for all channels. Used on transport stop so a clip that stopped
  /// mid-note doesn't leave a hung voice.
  void allNotesOff({int? channel});

  /// Close the output port. Idempotent.
  void close();
}
