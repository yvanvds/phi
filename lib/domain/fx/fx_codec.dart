import '../project/store/entity_payload_codec.dart';
import 'fx_definition.dart';

/// The per-kind [EntityPayloadCodec] for `fx.` entities (design
/// `docs/design/project-registry.md` §5 — the migration seam;
/// `docs/design/racks-and-voices.md` §5).
///
/// An `fx.` payload is a plain JSON map (an [FxDefinition]'s `toJson`), kept
/// map-native because an effect is created and edited through the ordinary
/// registry command layer, whose journal lines must be JSON-encodable — the same
/// choice the `mix.` and `voice.` codecs make. This codec normalises rather than
/// boxes: it round-trips through [FxDefinition] in both directions so a partial or
/// reordered map is filled with defaults and stamped at the current schema
/// [version].
class FxCodec implements EntityPayloadCodec {
  /// A `const` codec — it holds no state.
  const FxCodec();

  /// Schema v1 — the fx entity's first appearance (issue #204).
  @override
  int get version => 1;

  @override
  Object? encode(Object? payload) {
    if (payload == null) return null;
    if (payload is FxDefinition) return payload.toJson();
    return FxDefinition.fromJson(payload as Map<String, Object?>).toJson();
  }

  @override
  Object? decode(Object? json, int version) {
    if (json == null) return null;
    return FxDefinition.fromJson(json as Map<String, Object?>).toJson();
  }
}
