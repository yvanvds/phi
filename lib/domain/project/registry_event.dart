import 'entity_address.dart';

/// A single structural change to the [ProjectRegistry]'s namespace — the
/// fine-grained signal the engine's `RegistryMirror` seam (design
/// `docs/design/project-registry.md` §8) consumes to mirror the registry into
/// the embedded Python namespace.
///
/// The registry is a `ChangeNotifier`, so its coarse notification says only
/// *that* the tree changed. These events, delivered on
/// [ProjectRegistry.events], say *what* changed and *where*, in the address
/// vocabulary the mirror needs. A move is reported as one [RegistryEntityMoved]
/// whether it is a pure rename (same parent group) or a regroup (new parent);
/// the design draws that distinction from the two addresses, and the
/// engine-side binder does the classifying.
sealed class RegistryEvent {
  const RegistryEvent();
}

/// A node — entity or group — was created at [address].
final class RegistryEntityCreated extends RegistryEvent {
  const RegistryEntityCreated(this.address);

  /// The address of the newly created node.
  final EntityAddress address;

  @override
  bool operator ==(Object other) =>
      other is RegistryEntityCreated && other.address == address;

  @override
  int get hashCode => Object.hash(RegistryEntityCreated, address);

  @override
  String toString() => 'RegistryEntityCreated($address)';
}

/// The node at [from] was moved to [to] — a rename when the two share a parent
/// group, a regroup otherwise. A group carries its whole subtree in one move.
final class RegistryEntityMoved extends RegistryEvent {
  const RegistryEntityMoved(this.from, this.to);

  /// The address the node moved away from.
  final EntityAddress from;

  /// The address the node now lives at.
  final EntityAddress to;

  @override
  bool operator ==(Object other) =>
      other is RegistryEntityMoved && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(RegistryEntityMoved, from, to);

  @override
  String toString() => 'RegistryEntityMoved($from → $to)';
}

/// The node at [address] — and, for a group, its whole subtree — was removed.
final class RegistryEntityDeleted extends RegistryEvent {
  const RegistryEntityDeleted(this.address);

  /// The address of the removed node.
  final EntityAddress address;

  @override
  bool operator ==(Object other) =>
      other is RegistryEntityDeleted && other.address == address;

  @override
  int get hashCode => Object.hash(RegistryEntityDeleted, address);

  @override
  String toString() => 'RegistryEntityDeleted($address)';
}
