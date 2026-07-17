import '../entity_address.dart';
import '../project_command.dart';
import '../project_registry.dart';

/// Creates the group at [address] (design §6).
///
/// The registry's `createGroup` is idempotent, so [apply] records whether the
/// group already existed; [revert] removes it **only** when this command
/// actually created it. Undoing a no-op create is therefore itself a no-op,
/// and undo never deletes a group some earlier command owns.
class CreateGroupCommand implements ProjectCommand {
  CreateGroupCommand(this.registry, this.address);

  final ProjectRegistry registry;
  final EntityAddress address;

  bool _created = false;

  @override
  String get label => 'create group $address';

  @override
  Set<EntityAddress> get entitiesTouched => {address};

  @override
  void apply() {
    _created = registry.groupAt(address) == null;
    registry.createGroup(address);
  }

  @override
  void revert() {
    if (_created) registry.remove(address);
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'create_group',
    'address': address.format(),
  };
}
