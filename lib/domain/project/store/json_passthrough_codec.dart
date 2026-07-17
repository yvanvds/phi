import 'entity_payload_codec.dart';

/// The default [EntityPayloadCodec] used for any kind that has not registered
/// its own — the pre-migration behaviour of design
/// `docs/design/project-registry.md` §5.
///
/// It assumes the payload is *already* a JSON-compatible value (a `Map`, `List`,
/// or primitive, or `null`) and passes it straight through in both directions at
/// schema [version] `1`. That covers every entity the registry holds before its
/// kinds carry real payloads (the v1 migration epic), and keeps the store fully
/// exercisable now with plain-map payloads. A kind swaps in a real codec by
/// registering it under its kind; nothing else changes.
class JsonPassthroughCodec implements EntityPayloadCodec {
  /// A `const` codec — it holds no state.
  const JsonPassthroughCodec();

  @override
  int get version => 1;

  @override
  Object? encode(Object? payload) => payload;

  @override
  Object? decode(Object? json, int version) => json;
}
