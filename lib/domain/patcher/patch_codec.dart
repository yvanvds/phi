import '../project/store/entity_payload_codec.dart';
import 'patch_payload.dart';

/// The per-kind [EntityPayloadCodec] for `patch.` entities (design
/// `docs/design/project-registry.md` §5 — the migration seam;
/// `docs/design/patcher.md` §3).
///
/// A `patch.` payload is a plain JSON map (a [PatchPayload]'s `toJson`, i.e. the
/// engine dump under a `dump` key), kept map-native because a patch is edited
/// through the ordinary registry/gesture command layer whose journal lines must
/// be JSON-encodable — the same choice the `mix.`, `voice.` and `fx.` codecs
/// make. This codec normalises rather than boxes: it round-trips through
/// [PatchPayload] in both directions so a partial map is filled with defaults
/// and stamped at the current schema [version].
class PatchCodec implements EntityPayloadCodec {
  /// A `const` codec — it holds no state.
  const PatchCodec();

  /// Schema v1 — the patch entity's first appearance (issue #218).
  @override
  int get version => 1;

  @override
  Object? encode(Object? payload) {
    if (payload == null) return null;
    if (payload is PatchPayload) return payload.toJson();
    return PatchPayload.fromJson(
      (payload as Map).cast<String, Object?>(),
    ).toJson();
  }

  @override
  Object? decode(Object? json, int version) {
    if (json == null) return null;
    return PatchPayload.fromJson(
      (json as Map).cast<String, Object?>(),
    ).toJson();
  }
}
