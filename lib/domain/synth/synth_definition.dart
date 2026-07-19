import 'fm_synth.dart';
import 'sampler_synth.dart';
import 'sine_synth.dart';
import 'synth_kind.dart';
import 'va_synth.dart';

/// The payload of a `synth.` registry entity — a synthesis *recipe* the gateway
/// materialises into an engine voice pool (design
/// `docs/design/racks-and-voices.md` §3–§4).
///
/// **A definition, not an instance.** A `synth.` entity carries no engine
/// identity: it is kind + params + asset references only. Creating a *voice*
/// instantiates its own engine `Synth` from the shared definition; editing a
/// definition re-applies to every voice built from it (§3). The payload therefore
/// stays plain, immutable data.
///
/// One subclass per [SynthKind] ([SineSynth], [VaSynth], [FmSynth],
/// [SamplerSynth]); [fromJson] dispatches on the exhaustive [SynthKind] tag.
/// Each carries a [voiceCount] (the size of the engine voice pool) and
/// (de)serialises to a JSON map tagged with its [kind]. Kept `abstract` rather
/// than `sealed` so each subclass keeps its own file (project convention: one
/// class per file, and a sealed hierarchy must share a library).
abstract class SynthDefinition {
  const SynthDefinition();

  /// Rebuilds a definition from its decoded [json] map, dispatching on the
  /// `kind` tag. Throws a [FormatException] for a missing or unknown kind.
  factory SynthDefinition.fromJson(Map<String, Object?> json) {
    final kind = _kindByName(json['kind'] as String?);
    switch (kind) {
      case SynthKind.sine:
        return SineSynth.fromJson(json);
      case SynthKind.va:
        return VaSynth.fromJson(json);
      case SynthKind.fm:
        return FmSynth.fromJson(json);
      case SynthKind.sampler:
        return SamplerSynth.fromJson(json);
    }
  }

  /// Which of the four recipe shapes this definition is.
  SynthKind get kind;

  /// The number of voices in the engine pool the definition materialises — its
  /// polyphony ceiling.
  int get voiceCount;

  /// The definition as a JSON map, tagged with its [kind]. Keys are emitted in a
  /// stable order so an unchanged payload re-encodes byte-identically.
  Map<String, Object?> toJson();

  static SynthKind _kindByName(String? name) {
    for (final k in SynthKind.values) {
      if (k.name == name) return k;
    }
    throw FormatException('Unknown synth kind: "$name".');
  }
}
