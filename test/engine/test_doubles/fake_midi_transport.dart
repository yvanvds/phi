import 'package:clock/clock.dart';
import 'package:phi/engine/bridge/materialised_synth.dart';
import 'package:phi/engine/bridge/midi_transport.dart';
import 'package:phi/engine/bridge/transport_note.dart';

/// In-memory [MidiTransport] used in unit, widget, and integration tests.
///
/// Records every push so tests can assert the exact flattened note list a clip
/// produces — and that an edit while playing *re-pushes* — without touching
/// `package:yse` or its native library. The engine-driven counterpart of
/// [FakeMidiGateway]; the fake gateway mints one from [createTransport] and
/// keeps it on [FakeMidiGateway.transport] so tests can reach it.
///
/// Models the engine domain clock (issue #103): [beatPosition] free-runs as the
/// integral of [tempo] over elapsed time, read from `package:clock`'s
/// ambient [clock]. `fakeAsync` runs its callback inside `withClock`, so under a
/// `fakeAsync` test the beat advances exactly with `async.elapse`; in a
/// real-time integration test it advances with the wall clock — either way the
/// controller queries a real running clock, not a Dart accumulator it drives.
class FakeMidiTransport implements MidiTransport {
  /// The clock name and tempo the gateway minted this transport with.
  FakeMidiTransport({this.clockName = '', this.tempo = 120})
    : _mark = clock.now();

  final String clockName;

  /// Latest tempo pushed — the constructor value, then whatever [setTempo]
  /// last set.
  double tempo;

  /// Beats accumulated up to [_mark] at the tempo in force before it. Elapsed
  /// beats since [_mark] are added on read, so a mid-run [setTempo] integrates
  /// the two segments at their own tempos.
  double _accumBeats = 0;

  /// Wall-clock instant the current tempo segment began (play, construction, or
  /// the last [setTempo]).
  DateTime _mark;

  double _beatsSinceMark() =>
      clock.now().difference(_mark).inMicroseconds * 1e-6 * tempo / 60.0;

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

  /// Synths connected via [connectSynth] and not since disconnected — lets a
  /// test assert exactly which internal voices a session wired to this
  /// transport.
  final List<MaterialisedSynth> connectedSynths = [];

  /// Whether the external MIDI-out port is currently connected.
  bool midiOutConnected = false;

  @override
  void connectSynth(MaterialisedSynth synth) {
    calls.add('connectSynth');
    if (!connectedSynths.contains(synth)) connectedSynths.add(synth);
  }

  @override
  void disconnectSynth(MaterialisedSynth synth) {
    calls.add('disconnectSynth');
    connectedSynths.remove(synth);
  }

  @override
  void connectMidiOut() {
    calls.add('connectMidiOut');
    midiOutConnected = true;
  }

  @override
  void disconnectMidiOut() {
    calls.add('disconnectMidiOut');
    midiOutConnected = false;
  }

  @override
  void setTempo(double bpm) {
    // Fold the beats accrued at the old tempo before the rate changes, so the
    // running integral stays continuous across the switch.
    _accumBeats += _beatsSinceMark();
    _mark = clock.now();
    tempo = bpm;
  }

  @override
  double get beatPosition => _accumBeats + _beatsSinceMark();

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
