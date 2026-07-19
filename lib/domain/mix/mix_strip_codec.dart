import '../project/store/entity_payload_codec.dart';
import 'mix_strip.dart';

/// The per-kind [EntityPayloadCodec] for `mix.` entities and group buses (design
/// `docs/design/project-registry.md` §5 — the migration seam).
///
/// A `mix.` payload is a plain JSON map (a [MixStrip]'s `toJson`), kept map-native
/// because a strip is created and edited through the ordinary registry command
/// layer, whose journal lines must be JSON-encodable. This codec therefore
/// normalises rather than boxes: it round-trips the payload through [MixStrip] in
/// both directions so a partial or reordered map is filled with defaults and
/// stamped at the current schema [version].
///
/// Schema history:
/// - **v1** (#124): identity only (`name` + `voice`).
/// - **v2** (#136): added live mix state (`volume` + `muted` + `soloed`).
/// - **v3** (#166): added `return` + `sends`, and **dropped `name`** (the
///   one-name re-alignment, design §10 decision 1). A `name` key in an older
///   payload is simply no longer read — no migration, per that decision.
/// - **v4** (#204): added `inserts` — the ordered list of `fx.` addresses placed
///   on the bus (racks design §5). Additive: an older payload lacks it and
///   [MixStrip.fromJson] defaults it to an empty chain, so it loads forward
///   unchanged.
class MixStripCodec implements EntityPayloadCodec {
  /// A `const` codec — it holds no state.
  const MixStripCodec();

  /// Schema v4 (issue #204): the payload carries `inserts` alongside `return` +
  /// `sends`. Older versions decode forward via defaulted keys.
  @override
  int get version => 4;

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
