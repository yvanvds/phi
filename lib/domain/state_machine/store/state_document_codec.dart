import '../../project/store/entity_payload_codec.dart';
import 'state_document.dart';

/// The per-kind [EntityPayloadCodec] for `state.` entities (design
/// `docs/design/project-registry.md` §5, state-graph epic §3 — issue #240).
///
/// A `state.` payload is a plain JSON map (a [StateDocument]'s `toJson`), kept
/// map-native because states are created and edited through the ordinary
/// registry command layer, whose journal lines must be JSON-encodable (the
/// [MixStripCodec] precedent). The codec normalises rather than boxes: it
/// round-trips the payload through [StateDocument] in both directions, so a
/// partial map is filled with defaults and a corrupt one fails loudly.
/// Stamped at schema [version] `1`.
class StateDocumentCodec implements EntityPayloadCodec {
  /// A `const` codec — it holds no state.
  const StateDocumentCodec();

  @override
  int get version => 1;

  @override
  Object? encode(Object? payload) {
    if (payload == null) return null;
    if (payload is StateDocument) return payload.toJson();
    return StateDocument.fromJson(
      (payload as Map).cast<String, Object?>(),
    ).toJson();
  }

  @override
  Object? decode(Object? json, int version) {
    if (json == null) return null;
    return StateDocument.fromJson(
      (json as Map).cast<String, Object?>(),
    ).toJson();
  }
}
