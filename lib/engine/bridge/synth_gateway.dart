import '../../domain/synth/synth_definition.dart';
import 'materialised_synth.dart';

/// Abstract port over `package:yse`'s **synth** surface (design
/// `docs/design/racks-and-voices.md` §3–§4).
///
/// Materialises an engine synth from a `synth.` definition — the gateway half of
/// the racks epic. The session/voice layer depends on this interface, not on
/// `package:yse` directly, so the real FFI surface is touched in exactly one
/// place (`real_synth_gateway.dart`) and a fake stands in for tests. Mirrors
/// [YseGateway] and [MidiGateway] for the synth side.
///
/// A single call — [materialiseSynth] — builds the voice pool and hands back a
/// [MaterialisedSynth] handle that carries the rest of the lifecycle
/// (re-application, bus binding, disposal). Binding a whole *voice* (resolving
/// its bus from the mix registry, connecting it to a session transport) is the
/// engine layer's job (issue #208); this gateway is the primitive.
abstract interface class SynthGateway {
  /// Materialise an engine synth from [definition], registering its voice banks
  /// on the voice's allocated engine MIDI [channel] (`1..16`, design §3).
  ///
  /// Returns a [MaterialisedSynth] handle — the voice pool is built and its
  /// parameters applied, but it is **not** bound to a bus or connected to a
  /// transport yet; the caller drives those through the handle and the session
  /// transport.
  MaterialisedSynth materialiseSynth(
    SynthDefinition definition, {
    required int channel,
  });
}
