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

  /// Start (or resume) playback of the pushed events.
  void play();

  /// Stop playback.
  void stop();

  /// Whether the transport is currently playing.
  bool get isPlaying;

  /// Release the underlying engine clip and clock. Idempotent.
  void dispose();
}
