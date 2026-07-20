import 'midi_input_event.dart';
import 'midi_transport.dart';

/// Abstract port over `package:yse`'s MIDI **output** surface.
///
/// `EngineMidiController` depends on this interface, not on `package:yse`
/// directly, so tests can swap in a fake gateway and the production code is
/// the only place the real FFI surface is touched. Mirrors [YseGateway] for
/// the audio side. See `real_midi_gateway.dart` for the production
/// implementation and `test/.../fake_midi_gateway.dart` for the test double.
///
/// Since issue #101 note *dispatch* left this surface: timed notes are pushed
/// to a [MidiTransport] (minted by [createTransport]) that the engine plays
/// from the audio thread. What remains here is the genuinely immediate MIDI —
/// device enumeration, opening the port, and [allNotesOff] on stop.
abstract interface class MidiGateway {
  /// Number of MIDI output devices visible to the engine. `0` when none are
  /// present or the platform has no MIDI support.
  int get outputDeviceCount;

  /// Name of the output device at [id]. Pair with [open].
  String outputDeviceName(int id);

  // ─── MIDI input (design §4, §5) ─────────────────────────────────────────────
  //
  // Enumeration + open/close of the enabled input ports, plus an activity tick
  // for the UI dot. Ports are addressed by **name**, never by index — the
  // stored name resolves to the current index each open, so replugging keeps
  // working (design §5). Nothing is *routed* anywhere yet; consuming MIDI-in
  // belongs to the racks & voices epic (design §8). This epic only remembers
  // and opens the hardware and shows that it is receiving.

  /// Number of MIDI input devices visible to the engine. `0` when none are
  /// present or the platform has no MIDI support.
  int get inputDeviceCount;

  /// Name of the input device at [id]. Pair with [openInputs].
  String inputDeviceName(int id);

  /// The names of every visible MIDI input port, in listing order — the
  /// enumerated set the settings window presents as an input checklist.
  List<String> inputDeviceNames();

  /// Open exactly the input ports whose names are in [names], closing any
  /// currently-open input whose name is not in the set. Names are resolved to
  /// the current device index on each call, so a replug keeps working; a name
  /// that matches no visible port is skipped. Messages received on an open port
  /// pulse [inputActivity]. Idempotent for an unchanged [names] set.
  void openInputs(List<String> names);

  /// Close every open input port. Idempotent.
  void closeInputs();

  /// The names of the input ports currently open, in the order they were
  /// opened. Empty when none are open.
  List<String> get openInputNames;

  /// Broadcast stream that emits the **port name** on every MIDI message
  /// received on an open input port — the settings window flashes that port's
  /// activity dot (design §6). Each emission is a received-message tick.
  Stream<String> get inputActivity;

  /// Broadcast stream of **parsed note events** (note on/off + velocity +
  /// channel + port) received on an open input port (design §7). Decoded from
  /// the bridge's `MidiInParsedMessage`; non-note messages are filtered out.
  /// This *replaces nothing* — [inputActivity] still ticks for every message.
  /// Nothing routes these events yet; arming a voice and roll audition consume
  /// them in the racks surface (design §7, issue #211).
  Stream<MidiInputEvent> get inputEvents;

  /// Open the output device at [port]. A second call closes the previous
  /// port and opens the new one. No-op for an out-of-range [port].
  void open(int port);

  /// Whether an output port is currently open.
  bool get isOpen;

  /// Mint a [MidiTransport] bound to a fresh domain clock named [clockName],
  /// starting at [tempo] BPM, and routed to this gateway's output. The player
  /// pushes its flattened note list here and lets the engine dispatch it from
  /// the audio thread (issue #101).
  MidiTransport createTransport({
    required String clockName,
    required double tempo,
  });

  /// Immediately send a note-on to the open output port on [channel] — the
  /// **external-voice** audition path (design §7): arming an external voice, its
  /// test strip, and the roll preview send straight to the hardware instead of an
  /// internal synth. [channel] is `0..15` (the wire channel), [note] a MIDI note
  /// number `0..127`, [velocity] `0..127`. A no-op when no output port is open.
  void sendNoteOn({
    required int channel,
    required int note,
    required int velocity,
  });

  /// Immediately send a note-off to the open output port — the note-off half of
  /// the external-voice audition path. A no-op when no output port is open.
  void sendNoteOff({required int channel, required int note});

  /// Silence every sounding note. Pass a [channel] to scope it, or `null`
  /// for all channels. Used on transport stop so a clip that stopped
  /// mid-note doesn't leave a hung voice.
  void allNotesOff({int? channel});

  /// Close the output port. Idempotent.
  void close();
}
