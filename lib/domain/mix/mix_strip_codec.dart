import '../project/store/entity_payload_codec.dart';
import 'mix_strip.dart';

/// The per-kind [EntityPayloadCodec] for `mix.` entities (design
/// `docs/design/project-registry.md` §5 — the migration seam).
///
/// A `mix.` entity's payload is a plain JSON map (a [MixStrip]'s `toJson`), kept
/// map-native because a strip is created and edited through the ordinary registry
/// command layer, whose journal lines must be JSON-encodable. This codec
/// therefore normalises rather than boxes: it round-trips the payload through
/// [MixStrip] in both directions so a partial or reordered map is filled with
/// defaults and stamped at the current schema [version].
///
/// #124 (schema v1) persisted only a strip's identity (`name` + `voice`); issue
/// #136 adds the live mixing state (`volume` + `muted` + `soloed`), bumping the
/// schema to **v2**. The migration is additive and needs no special-casing: a v1
/// payload simply lacks those keys, and [MixStrip.fromJson] defaults them to
/// unity volume, unmuted and unsoloed — so an older file loads forward unchanged.
class MixStripCodec implements EntityPayloadCodec {
  /// A `const` codec — it holds no state.
  const MixStripCodec();

  /// Schema v2 (issue #136): the payload now carries the live mix state. v1 was
  /// identity only; [decode] migrates it forward via defaulted keys.
  @override
  int get version => 2;

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
