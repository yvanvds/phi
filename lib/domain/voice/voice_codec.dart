import '../project/store/entity_payload_codec.dart';
import 'voice_definition.dart';

/// The per-kind [EntityPayloadCodec] for `voice.` entities (design
/// `docs/design/project-registry.md` §5 — the migration seam;
/// `docs/design/racks-and-voices.md` §3).
///
/// A `voice.` payload is a plain JSON map (a [VoiceDefinition]'s `toJson`), kept
/// map-native because a voice is created and edited through the ordinary registry
/// command layer, whose journal lines must be JSON-encodable — the same choice
/// the `mix.` codec makes. This codec normalises rather than boxes: it round-trips
/// the payload through [VoiceDefinition] in both directions so a partial or
/// reordered map is filled with defaults and stamped at the current schema
/// [version].
class VoiceCodec implements EntityPayloadCodec {
  /// A `const` codec — it holds no state.
  const VoiceCodec();

  /// Schema v1 — the voice entity's first appearance (issue #204).
  @override
  int get version => 1;

  @override
  Object? encode(Object? payload) {
    if (payload == null) return null;
    if (payload is VoiceDefinition) return payload.toJson();
    return VoiceDefinition.fromJson(payload as Map<String, Object?>).toJson();
  }

  @override
  Object? decode(Object? json, int version) {
    if (json == null) return null;
    return VoiceDefinition.fromJson(json as Map<String, Object?>).toJson();
  }
}
