import 'package:yse/yse.dart';

import 'midi_transport.dart';
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

  bool _connected = false;
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
  void play() {
    if (_disposed) return;
    // Connect to the gateway's output lazily: the controller opens the port
    // just before the first play, so the MidiOut is ready by now.
    if (!_connected) {
      final out = _gateway.midiOut;
      if (out != null) {
        _clip.connectMidiOut(out);
        _connected = true;
      }
    }
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
