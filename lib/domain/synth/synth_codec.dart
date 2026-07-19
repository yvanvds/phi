import '../project/store/entity_payload_codec.dart';
import 'synth_definition.dart';

/// The per-kind [EntityPayloadCodec] for `synth.` entities (design
/// `docs/design/project-registry.md` §5 — the migration seam;
/// `docs/design/racks-and-voices.md` §4).
///
/// A `synth.` payload is a plain JSON map (a [SynthDefinition]'s `toJson`, tagged
/// with its `kind`), kept map-native because a definition is created and edited
/// through the ordinary registry command layer, whose journal lines must be
/// JSON-encodable — the same choice the `mix.`, `voice.` and `fx.` codecs make.
/// This codec normalises rather than boxes: it round-trips through
/// [SynthDefinition.fromJson] (which dispatches on the `kind` tag) in both
/// directions so a partial or reordered map is filled with defaults and stamped at
/// the current schema [version].
class SynthCodec implements EntityPayloadCodec {
  /// A `const` codec — it holds no state.
  const SynthCodec();

  /// Schema v1 — the synth entity's first appearance (issue #204).
  @override
  int get version => 1;

  @override
  Object? encode(Object? payload) {
    if (payload == null) return null;
    if (payload is SynthDefinition) return payload.toJson();
    return SynthDefinition.fromJson(payload as Map<String, Object?>).toJson();
  }

  @override
  Object? decode(Object? json, int version) {
    if (json == null) return null;
    return SynthDefinition.fromJson(json as Map<String, Object?>).toJson();
  }
}
