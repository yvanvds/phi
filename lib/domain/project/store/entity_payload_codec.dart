/// The per-kind seam that (de)serialises an entity's opaque payload — the
/// migration point of design `docs/design/project-registry.md` §5 ("Per-kind
/// `version` fields are the migration seam").
///
/// The registry core is kind-generic: an entity's payload is an `Object?` it
/// never inspects. The store therefore cannot know how to turn a clip, voice or
/// mix bus into JSON on its own. Each kind supplies a codec instead, keyed by
/// kind in the [ProjectStore]. A codec declares the schema [version] it writes
/// (stamped into every entity file), [encode]s a payload to a JSON-compatible
/// value, and [decode]s one back — receiving the file's stored version so a
/// newer codec can migrate an older file forward.
///
/// Kinds populate as their epics land (voices, synths, …). Until then the store
/// falls back to a pass-through codec, so entities with `null` or already-JSON
/// payloads round-trip with no per-kind code.
abstract interface class EntityPayloadCodec {
  /// The schema version this codec writes — stamped into each entity file as
  /// `version` and handed back to [decode] on load.
  int get version;

  /// Turns a payload into a JSON-compatible value (map, list, or primitive), or
  /// `null` for an entity that carries no payload.
  Object? encode(Object? payload);

  /// Rebuilds a payload from the value [encode] produced, given the [version] it
  /// was written with (so an upgraded codec can migrate an older file).
  Object? decode(Object? json, int version);
}
