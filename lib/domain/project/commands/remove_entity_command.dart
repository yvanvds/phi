import '../entity_address.dart';
import '../project_command.dart';
import '../project_registry.dart';

/// Removes the *entity* at [address], capturing its payload and references
/// during [apply] so [revert] can put it back exactly — including its edges in
/// the back-reference index (design §4, §6).
///
/// Targets a single entity, not a group subtree: reverting a group deletion
/// must restore a whole subtree, which is a larger command than this. If
/// nothing (or a group) sits at [address], [apply] is the registry's tolerant
/// no-op and [revert] restores nothing.
///
/// **Delete warnings** are a *pre-flight* concern, not this command's job: a
/// surface calls `registry.impactOfRemoving(address)` and decides whether to
/// proceed before ever running this command.
class RemoveEntityCommand implements ProjectCommand {
  RemoveEntityCommand(this.registry, this.address);

  final ProjectRegistry registry;
  final EntityAddress address;

  Object? _payload;
  Set<EntityAddress> _references = const {};
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
    _references = entity?.references ?? const {};
    registry.remove(address);
  }

  @override
  void revert() {
    if (_had) {
      registry.createEntity(
        address,
        payload: _payload,
        references: _references,
      );
    }
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'remove_entity',
    'address': address.format(),
  };
}
