import '../../domain/synth/synth_definition.dart';
import '../../domain/synth/synth_kind.dart';

/// A live engine synth materialised from a `synth.` definition — the handle a
/// voice drives (design `docs/design/racks-and-voices.md` §3).
///
/// Minted by [SynthGateway.materialiseSynth], which builds the engine voice pool
/// from a [SynthDefinition] and registers it on the voice's allocated MIDI
/// [channel]. The handle then lets its owner:
///
/// - **re-apply** an edited definition ([applyDefinition]) — live setters where
///   the engine allows, a full rebuild of the voice pool when it cannot (an FM
///   bank swap, a sampler instrument swap, a voice-count or kind change; see
///   `SynthMaterialisation.needsRematerialise`);
/// - **bind** its output to a mix bus ([bindToBus]) through a
///   `Sound.fromSynth`, re-pointing that binding when the voice's bus changes;
/// - **dispose** it, tearing the `Sound` down before the `Synth` — the
///   leak-safe order the engine requires.
///
/// The interface is yse-free so the engine-bridge boundary holds and a fake can
/// stand in for the whole surface in tests. `SynthGateway` and this handle are
/// the *primitives*; wiring a whole voice (its transport connections, its bus
/// from the mix registry) is the session layer's job (issue #208).
abstract interface class MaterialisedSynth {
  /// Which recipe kind this synth was built from — follows [definition].
  SynthKind get kind;

  /// The engine MIDI channel (`1..16`) this synth's voice banks filter on — the
  /// stable channel the voice was allocated (design §3).
  int get channel;

  /// The definition currently applied — the last value handed to the
  /// constructor or [applyDefinition].
  SynthDefinition get definition;

  /// The mix-bus channel id this synth's [Sound] is bound to, or `null` when it
  /// is bound to the master bus (or not yet bound at all).
  int? get boundBus;

  /// Re-apply [definition] to the live synth. Applies parameters in place when
  /// the engine allows it; otherwise rebuilds the voice pool, re-binding the
  /// output to the same bus. A rebuild mints a fresh engine synth, so any
  /// transport connected to this handle must reconnect afterwards (issue #208).
  void applyDefinition(SynthDefinition definition);

  /// Bind (or re-bind) this synth's output to the mix bus with id
  /// [busChannelId], or the master bus when it is `null`. The first call wraps
  /// the synth in a `Sound.fromSynth` on that bus; a later call moves the
  /// existing sound — the voice re-pointing behind a stable identity (design §3).
  void bindToBus(int? busChannelId);

  /// Immediately start [note] (a MIDI note number, `0..127`) on this synth's
  /// [channel] — the **audition** path (design §7). Bypasses the transport for
  /// zero-latency response, so arming a voice, the on-screen test strip, and the
  /// roll preview all sound the moment the performer acts. [velocity] is
  /// normalised `[0, 1]`.
  void noteOn(int note, {double velocity});

  /// Immediately release [note] on this synth's [channel] — the note-off half of
  /// the audition path.
  void noteOff(int note);

  /// Release **every** held note on this synth, on all channels — the panic
  /// safety net (issue #264, design `docs/design/midi-recording.md` §6). Unlike
  /// the transport's scoped stop, this reaches notes started outside any
  /// transport (a held arm-for-input / test-strip audition), so a hung voice
  /// never survives a panic. Voices enter their normal release; they are not cut.
  /// Idempotent — safe to call when nothing is sounding.
  void allNotesOff();

  /// Release the engine resources — the `Sound` first, then the `Synth` — the
  /// order the engine requires to avoid a dangling voice-pool render. Idempotent.
  void dispose();
}
