import '../../domain/synth/fm_synth.dart';
import '../../domain/synth/sampler_synth.dart';
import '../../domain/synth/synth_definition.dart';
import '../../domain/synth/synth_kind.dart';

/// Pure decision for whether a `synth.` definition edit re-applies **live** or
/// forces a **re-materialisation** of the engine voice pool (design
/// `docs/design/racks-and-voices.md` §3 — "Param re-application … setters are
/// live; bank/instrument swaps re-materialise").
///
/// Kept yse-free and static so both the real gateway and its fake share one
/// rule, and so the rule itself is unit-tested without the native library.
///
/// A re-materialisation is needed when the change cannot be expressed through a
/// live setter on the existing voice pool:
///
/// - **the kind changed** — a different voice type entirely;
/// - **the voice count changed** — voices are cloned *before* the synth plays
///   and the engine rejects an `add*Voices` afterwards, so a new pool size means
///   a fresh synth;
/// - **an FM bank swap** — pointing at a different `.syx` bank;
/// - **a sampler instrument swap** — a different `.sfz` asset or single-sample
///   recipe.
///
/// Everything else — VA panel params, an FM patch/algorithm/feedback/operator
/// tweak within the *same* bank — is a live setter and returns `false`.
abstract final class SynthMaterialisation {
  /// Whether moving from [current] to [next] requires rebuilding the engine
  /// voice pool rather than re-applying parameters in place.
  static bool needsRematerialise(
    SynthDefinition current,
    SynthDefinition next,
  ) {
    if (current.kind != next.kind) return true;
    if (current.voiceCount != next.voiceCount) return true;
    switch (next.kind) {
      case SynthKind.sine:
      case SynthKind.va:
        // sine carries only its voice count (handled above); every VA field is
        // a glitch-free live setter.
        return false;
      case SynthKind.fm:
        // A patch/algorithm/operator edit is live; only swapping the source
        // bank asset rebuilds.
        return (current as FmSynth).bankAsset != (next as FmSynth).bankAsset;
      case SynthKind.sampler:
        // The sampler has no live setters — any change to its one instrument
        // source rebuilds.
        final c = current as SamplerSynth;
        final n = next as SamplerSynth;
        return c.sfzAsset != n.sfzAsset || c.recipe != n.recipe;
    }
  }
}
