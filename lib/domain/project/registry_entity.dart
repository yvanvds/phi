import 'registry_node.dart';

/// A named leaf in the registry tree — one entity of a [kind] (clip, mix bus,
/// voice, …) owning its opaque [payload].
///
/// The tree is *kind-generic*: a single registry holds entities of every kind
/// side by side, so the payload can't be a single static type. It is therefore
/// an `Object?` the kind's own layer casts back — the registry core cares about
/// names, addresses and structure, never about what a clip or a mix bus is.
/// Serialization, editing-via-commands, and the back-reference index all arrive
/// in later epic issues; here the payload is simply set once at creation.
class RegistryEntity extends RegistryNode {
  RegistryEntity({required String name, required this.kind, this.payload})
    : super(name);

  /// The namespace this entity belongs to — matches the [kind] of the
  /// [EntityAddress] it lives at. Immutable: a move never crosses kinds.
  final String kind;

  /// The entity's domain object, opaque to the registry. `null` until a kind's
  /// own layer supplies one.
  final Object? payload;
}
