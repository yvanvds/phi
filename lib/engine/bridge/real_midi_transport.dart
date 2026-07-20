import 'package:yse/yse.dart';

import 'materialised_synth.dart';
import 'midi_transport.dart';
import 'real_materialised_synth.dart';
import 'real_midi_gateway.dart';
import 'transport_note.dart';

/// Production [MidiTransport] backed by `package:yse`'s `DomainClock` +
/// `ClipTransport` (issue #101).
///
/// Owns a named [DomainClock] and a [ClipTransport] bound to it. The clip is
/// routed to the [RealMidiGateway]'s already-open [MidiOut] the first time it
/// plays, so external MIDI output goes through the one port the gateway opened
/// — no second device handle. Because the engine dispatches from the audio
/// thread, playback stays steady under UI-isolate load.
///
/// Minted by [RealMidiGateway.createTransport]; construct nothing directly.
class RealMidiTransport implements MidiTransport {
  RealMidiTransport(this._gateway, this._clock, this._clip);

  final RealMidiGateway _gateway;
  final DomainClock _clock;
  final ClipTransport _clip;

  bool _midiConnected = false;
  bool _disposed = false;

  @override
  void setEvents(List<TransportNote> events, {required double loopBeats}) {
    if (_disposed) return;
    _clip.setEvents([
      for (final e in events)
        ClipEvent(
          startBeat: e.startBeat,
          durationBeats: e.durationBeats,
          // Phi channels are 0..15; the engine wire is 1..16.
          channel: (e.channel + 1).clamp(1, 16),
          pitch: e.pitch,
          velocity: e.velocity,
          pitchBend: e.pitchBend,
        ),
    ], loopBeats: loopBeats);
  }

  @override
  void setTempo(double bpm) {
    if (_disposed) return;
    _clock.setTempo(bpm);
  }

  @override
  double get beatPosition => _disposed ? 0 : _clock.beatPosition;

  @override
  void connectSynth(MaterialisedSynth synth) {
    if (_disposed || synth is! RealMaterialisedSynth) return;
    _clip.connectSynth(synth.synth);
  }

  @override
  void disconnectSynth(MaterialisedSynth synth) {
    if (_disposed || synth is! RealMaterialisedSynth) return;
    _clip.disconnectSynth(synth.synth);
  }

  @override
  void connectMidiOut() {
    if (_disposed || _midiConnected) return;
    // The controller opens the port just before the first play, so the MidiOut
    // is ready by the time a session first connects.
    final out = _gateway.midiOut;
    if (out != null) {
      _clip.connectMidiOut(out);
      _midiConnected = true;
    }
  }

  @override
  void disconnectMidiOut() {
    if (_disposed || !_midiConnected) return;
    final out = _gateway.midiOut;
    if (out != null) _clip.disconnectMidiOut(out);
    _midiConnected = false;
  }

  @override
  void play() {
    if (_disposed) return;
    // The owning session drives [connectMidiOut] / [connectSynth] from its
    // flatten step by the voices its clip routes to (design §6, issue #208) —
    // it pushes events (and reconciles connections) just before this call — so
    // an internal-only clip no longer bleeds to the external port.
    _clip.play();
  }

  @override
  void stop() {
    if (_disposed) return;
    _clip.stop();
  }

  @override
  bool get isPlaying => !_disposed && _clip.isPlaying;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // The clip is bound to the clock, so drop it first, then the clock.
    _clip.dispose();
    _clock.dispose();
  }
}
