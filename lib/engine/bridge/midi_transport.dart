import 'materialised_synth.dart';
import 'transport_note.dart';

/// Abstract port over the engine's **clip transport** — the audio-thread
/// dispatcher that owns *when* every note fires (issue #101).
///
/// `EngineMidiController` pushes a flattened, beat-timed [TransportNote] list
/// plus the loop length here on play and again whenever the interpreted output
/// changes (a clip edit, chip toggle, hot-reload, or state/variable flip
/// re-evaluating the graph). The engine swaps the event buffer at the next
/// audio-block boundary, so an edit is heard within one block without the UI
/// isolate ever dispatching a note.
///
/// Minted by [MidiGateway.createTransport] so the transport shares the
/// gateway's already-open output. Tests swap in a fake counterpart that records
/// the pushed events; production wraps a `package:yse` `DomainClock` +
/// `ClipTransport` (see `real_midi_transport.dart`).
abstract interface class MidiTransport {
  /// Replace the note list and loop length in one push. Safe while [isPlaying]
  /// — the engine applies the new list at the next audio-block boundary and
  /// still delivers note-offs for notes sounding across the swap. A
  /// [loopBeats] `<= 0` disables looping (the events fire once); an empty
  /// [events] list clears the transport.
  void setEvents(List<TransportNote> events, {required double loopBeats});

  /// Set the bound domain clock's tempo in BPM. Tempo lives in the clock, not
  /// in the pushed note data, so a tempo change never forces a re-push.
  void setTempo(double bpm);

  // ─── connections (design `docs/design/racks-and-voices.md` §6) ──────────────
  //
  // A session transport broadcasts its events to every connected sink and lets
  // the sink's voice banks filter by MIDI channel: `connectSynth` for each
  // internal voice its routed output reaches, `connectMidiOut` when any routed
  // voice is external. The session drives these as it resolves which voices a
  // clip routes to (issue #208); this surface only exposes them.

  /// Route this transport to an internal [synth], driven from the audio thread.
  /// Connecting the same synth twice is a no-op. [synth] must outlive the
  /// connection (or be disconnected first) — a re-materialised synth is a fresh
  /// engine object, so its owner reconnects after an [applyDefinition] rebuild.
  void connectSynth(MaterialisedSynth synth);

  /// Stop routing this transport to [synth]. A no-op when it was not connected.
  void disconnectSynth(MaterialisedSynth synth);

  /// Route this transport to the gateway's open external MIDI-out port.
  /// Idempotent — the first play already connects it lazily.
  void connectMidiOut();

  /// Stop routing this transport to the external MIDI-out port. Idempotent.
  void disconnectMidiOut();

  /// The bound domain clock's current beat position — the running integral of
  /// tempo, advanced on the audio thread (issue #103). This is the timing
  /// authority the UI queries at frame rate to re-anchor the display playhead
  /// and Scene agent spawn/despawn to the engine clock, rather than integrating
  /// a Dart-side accumulator that jitters under UI-isolate load. Free-running:
  /// the clock keeps advancing regardless of transport play state, so callers
  /// that want a play-relative position subtract the beat captured at [play].
  double get beatPosition;

  /// Start (or resume) playback of the pushed events.
  void play();

  /// Stop playback.
  void stop();

  /// Whether the transport is currently playing.
  bool get isPlaying;

  /// Release the underlying engine clip and clock. Idempotent.
  void dispose();
}
