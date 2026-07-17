import '../project/store/entity_payload_codec.dart';
import 'mix_strip.dart';

/// The per-kind [EntityPayloadCodec] for `mix.` entities (design
/// `docs/design/project-registry.md` §5 — the migration seam).
///
/// A `mix.` entity's payload is a plain JSON map (a [MixStrip]'s `toJson`), kept
/// map-native because a strip is created through the ordinary registry command
/// layer, whose journal lines must be JSON-encodable. This codec therefore
/// normalises rather than boxes: it round-trips the payload through [MixStrip] in
/// both directions so a partial or reordered map is filled with defaults and
/// stamped at schema [version] `1`.
class MixStripCodec implements EntityPayloadCodec {
  /// A `const` codec — it holds no state.
  const MixStripCodec();

  @override
  int get version => 1;

  @override
  Object? encode(Object? payload) {
    if (payload == null) return null;
    if (payload is MixStrip) return payload.toJson();
    return MixStrip.fromJson(payload as Map<String, Object?>).toJson();
  }

  @override
  Object? decode(Object? json, int version) {
    if (json == null) return null;
    return MixStrip.fromJson(json as Map<String, Object?>).toJson();
  }
}
