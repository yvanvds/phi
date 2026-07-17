import '../entity_address.dart';
import '../project_command.dart';
import '../project_registry.dart';

/// Removes the *entity* at [address], capturing its payload during [apply] so
/// [revert] can put it back exactly (design §6).
///
/// Targets a single entity, not a group subtree: reverting a group deletion
/// must restore a whole subtree, which belongs with delete warnings and the
/// back-reference index (#120). If nothing (or a group) sits at [address],
/// [apply] is the registry's tolerant no-op and [revert] restores nothing.
class RemoveEntityCommand implements ProjectCommand {
  RemoveEntityCommand(this.registry, this.address);

  final ProjectRegistry registry;
  final EntityAddress address;

  Object? _payload;
  bool _had = false;

  @override
  String get label => 'delete $address';

  @override
  Set<EntityAddress> get entitiesTouched => {address};

  @override
  void apply() {
    final entity = registry.entityAt(address);
    _had = entity != null;
    _payload = entity?.payload;
    registry.remove(address);
  }

  @override
  void revert() {
    if (_had) registry.createEntity(address, payload: _payload);
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'remove_entity',
    'address': address.format(),
  };
}
