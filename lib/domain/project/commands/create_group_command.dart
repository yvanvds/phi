import '../entity_address.dart';
import '../project_command.dart';
import '../project_registry.dart';

/// Creates the group at [address] (design §6), optionally carrying an entity
/// [payload] and the [references] it declares — a group bus's fader/sends
/// (issue #165, design `docs/design/mix.md` §3).
///
/// The registry's `createGroup` is idempotent, so [apply] records whether the
/// group already existed; [revert] removes it **only** when this command
/// actually created it. Undoing a no-op create is therefore itself a no-op,
/// and undo never deletes a group some earlier command owns. [payload] and
/// [references] must be JSON-encodable so the command journals (the crash
/// recovery contract) — a group bus carries a plain payload map, as `mix.`
/// entities do.
class CreateGroupCommand implements ProjectCommand {
  CreateGroupCommand(
    this.registry,
    this.address, {
    this.payload,
    this.references = const {},
  });

  final ProjectRegistry registry;
  final EntityAddress address;
  final Object? payload;
  final Set<EntityAddress> references;

  bool _created = false;

  @override
  String get label => 'create group $address';

  @override
  Set<EntityAddress> get entitiesTouched => {address};

  @override
  void apply() {
    _created = registry.groupAt(address) == null;
    registry.createGroup(address, payload: payload, references: references);
  }

  @override
  void revert() {
    if (_created) registry.remove(address);
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'create_group',
    'address': address.format(),
    if (payload != null) 'payload': payload,
    if (references.isNotEmpty)
      'references': references.map((r) => r.format()).toList(),
  };
}
