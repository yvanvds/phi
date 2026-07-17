import '../entity_address.dart';
import '../project_command.dart';
import '../project_registry.dart';

/// Creates an entity at [address], carrying [payload] and declaring
/// [references] (the addresses it points at, §4). [revert] removes it, so a
/// create followed by an undo leaves the tree — and the back-reference index —
/// as they were.
///
/// Aimed at the common "create in place" case, where the parent group already
/// exists. If [address] has missing ancestor groups, [apply] auto-creates them
/// (`mkdir -p`) but [revert] removes only the entity, not those groups — an
/// empty group is harmless and tracking auto-created ancestors is out of scope
/// for this layer.
class CreateEntityCommand implements ProjectCommand {
  CreateEntityCommand(
    this.registry,
    this.address, {
    this.payload,
    this.references = const {},
  });

  final ProjectRegistry registry;
  final EntityAddress address;
  final Object? payload;
  final Set<EntityAddress> references;

  @override
  String get label => 'create $address';

  @override
  Set<EntityAddress> get entitiesTouched => {address};

  @override
  void apply() =>
      registry.createEntity(address, payload: payload, references: references);

  @override
  void revert() => registry.remove(address);

  @override
  Map<String, Object?> toJson() => {
    'type': 'create_entity',
    'address': address.format(),
    if (payload != null) 'payload': payload,
    if (references.isNotEmpty)
      'references': references.map((r) => r.format()).toList(),
  };
}
