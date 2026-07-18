import 'entity_address.dart';
import 'reference_source.dart';
import 'registry_node.dart';

/// A named leaf in the registry tree — one entity of a [kind] (clip, mix bus,
/// voice, …) owning its opaque [payload].
///
/// The tree is *kind-generic*: a single registry holds entities of every kind
/// side by side, so the payload can't be a single static type. It is therefore
/// an `Object?` the kind's own layer casts back — the registry core cares about
/// names, addresses and structure, never about what a clip or a mix bus is.
///
/// **Outgoing references.** An entity may point at other entities by address
/// (`voice.bells` → `mix.perc`). [references] is that set — the input to the
/// registry's back-reference index (design §4). It is derived from [payload]
/// when the payload is a [ReferenceSource] (the authoritative case once kinds
/// carry real payloads); otherwise it is the set declared at construction, which
/// is how pre-migration entities (plain domain payloads, or none) still declare
/// their edges.
class RegistryEntity extends RegistryNode {
  /// Builds an entity, resolving [references] from [payload] when the payload is
  /// a [ReferenceSource], else from the explicitly declared set.
  factory RegistryEntity({
    required String name,
    required String kind,
    Object? payload,
    Set<EntityAddress> references = const {},
  }) {
    return RegistryEntity._(
      name: name,
      kind: kind,
      payload: payload,
      references: resolveReferences(payload, references),
    );
  }

  RegistryEntity._({
    required String name,
    required this.kind,
    required this.payload,
    required this.references,
  }) : super(name);

  /// The namespace this entity belongs to — matches the [kind] of the
  /// [EntityAddress] it lives at. Immutable: a move never crosses kinds.
  final String kind;

  /// The entity's domain object, opaque to the registry. `null` until a kind's
  /// own layer supplies one.
  final Object? payload;

  /// The addresses this entity points at — the entity's outgoing edges in the
  /// back-reference index. Unmodifiable; empty when the entity references
  /// nothing.
  final Set<EntityAddress> references;
}
