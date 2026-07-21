import '../project/store/entity_payload_codec.dart';
import 'code_script.dart';

/// The per-kind [EntityPayloadCodec] for `code.` entities (design
/// `docs/design/project-registry.md` §5, live-coding epic §5) — the persistence
/// of a live-coding script's source text (issue #235).
///
/// A [CodeScript] is just its [CodeScript.source] wrapped in a one-key map, so
/// the codec is a thin envelope: [encode] emits the payload map verbatim and
/// [decode] rebuilds the value type. The round-trip is byte-identical — a saved
/// script reopens exactly as written. Stamped at schema [version] `1`.
class CodeScriptCodec implements EntityPayloadCodec {
  /// A `const` codec — it holds no state.
  const CodeScriptCodec();

  @override
  int get version => 1;

  @override
  Object? encode(Object? payload) {
    if (payload == null) return null;
    // Payloads are kept map-native in the registry (the journal contract), so a
    // stored payload is usually already the map; a live [CodeScript] flattens.
    if (payload is CodeScript) return payload.toJson();
    if (payload is Map) return payload.cast<String, Object?>();
    throw ArgumentError.value(payload, 'payload', 'not a code script payload');
  }

  @override
  Object? decode(Object? json, int version) {
    if (json == null) return null;
    return CodeScript.fromJson((json as Map).cast<String, Object?>());
  }
}
