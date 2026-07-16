import 'package:phi/engine/bridge/midi_transport.dart';
import 'package:phi/engine/bridge/transport_note.dart';

/// In-memory [MidiTransport] used in unit, widget, and integration tests.
///
/// Records every push so tests can assert the exact flattened note list a clip
/// produces — and that an edit while playing *re-pushes* — without touching
/// `package:yse` or its native library. The engine-driven counterpart of
/// [FakeMidiGateway]; the fake gateway mints one from [createTransport] and
/// keeps it on [FakeMidiGateway.transport] so tests can reach it.
class FakeMidiTransport implements MidiTransport {
  /// The clock name and tempo the gateway minted this transport with.
  FakeMidiTransport({this.clockName = '', this.tempo = 120});

  final String clockName;

  /// Latest tempo pushed — the constructor value, then whatever [setTempo]
  /// last set.
  double tempo;

  /// The most recently pushed event list. Empty until the first [setEvents].
  List<TransportNote> events = const [];

  /// Loop length in beats from the most recent [setEvents].
  double loopBeats = 0;

  /// How many times [setEvents] was called — one per push. The initial play
  /// push is 1; each re-push on a revision bump adds another.
  int pushCount = 0;

  bool _playing = false;

  /// Ordered log of lifecycle calls (`play` / `stop` / `dispose`), for tests
  /// that assert the transport was actually driven.
  final List<String> calls = [];

  @override
  void setEvents(List<TransportNote> events, {required double loopBeats}) {
    this.events = List<TransportNote>.of(events);
    this.loopBeats = loopBeats;
    pushCount++;
  }

  @override
  void setTempo(double bpm) => tempo = bpm;

  @override
  void play() {
    _playing = true;
    calls.add('play');
  }

  @override
  void stop() {
    _playing = false;
    calls.add('stop');
  }

  @override
  bool get isPlaying => _playing;

  @override
  void dispose() {
    _playing = false;
    calls.add('dispose');
  }
}
