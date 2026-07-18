import '../project/store/entity_payload_codec.dart';
import 'store/clip_document.dart';

/// The per-kind [EntityPayloadCodec] for `clip.` entities (design
/// `docs/design/project-registry.md` §5) — it (de)serialises a clip's source
/// notes **and its interpretation** (the transform chain / graph).
///
/// A clip is "interpreted, not played": the source [MidiClip] is the authored
/// material, and the [MidiTransformChain] / [MidiTransformGraph] is how it is
/// read. #124 (schema v1) persisted only the source; issue #135 adds the
/// interpretation, bumping the schema to **v2** whose payload is a whole
/// [ClipDocument] (`source` + `mode` + `chain` + optional `graph`).
///
/// Like the `mix.` codec, the payload is kept **map-native**: a clip edit is
/// recorded through the command layer (whose journal lines must be JSON), so the
/// registry carries a `ClipDocument`'s `toJson` map rather than a boxed object.
/// This codec therefore normalises rather than boxes — it round-trips the map
/// through the v2 shape in both directions and **migrates a v1 payload** (a bare
/// clip, no `source` key) forward to a document with an empty chain.
class MidiClipCodec implements EntityPayloadCodec {
  /// A `const` codec — it holds no state.
  const MidiClipCodec();

  /// Schema v2 (issue #135): the payload is a whole [ClipDocument]. v1 was the
  /// bare source clip; [decode] migrates it forward.
  @override
  int get version => 2;

  @override
  Object? encode(Object? payload) {
    if (payload == null) return null;
    if (payload is ClipDocument) return payload.toJson();
    if (payload is Map) return _asV2(payload.cast<String, Object?>());
    throw ArgumentError.value(
      payload,
      'payload',
      'a clip payload must be a ClipDocument or its JSON map',
    );
  }

  @override
  Object? decode(Object? json, int version) {
    if (json == null) return null;
    return _asV2((json as Map).cast<String, Object?>());
  }

  /// Normalises [map] to the v2 document shape, wrapping a v1 payload (a bare
  /// clip with no `source` sub-map) as `{source: clip, mode: chain, chain: []}`.
  /// Pure JSON — no object round-trip — so a live-coded (custom) transform is
  /// never downgraded on a plain re-save.
  Map<String, Object?> _asV2(Map<String, Object?> map) {
    if (map['source'] is Map) return Map<String, Object?>.of(map);
    return <String, Object?>{
      'source': map,
      'mode': 'chain',
      'chain': const <Object?>[],
    };
  }
}
