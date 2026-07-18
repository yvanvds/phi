import '../entity_address.dart';
import '../project_command.dart';
import '../project_registry.dart';

/// Replaces the payload of the *group* at [address] with [payload] — the group
/// counterpart of [UpdateEntityPayloadCommand] (issue #165, design
/// `docs/design/mix.md` §3).
///
/// A group-bus edit (its fader/mute/solo, or a re-routed send) mutates the live
/// group and publishes a fresh snapshot of its payload; this command carries
/// that snapshot so the change is dirty-tracked and journaled like any other.
/// [apply] captures the previous payload so [revert] restores it exactly, and
/// [toJson] carries the new payload verbatim (already JSON — the journal
/// contract) so a forward replay reproduces the update.
class UpdateGroupPayloadCommand implements ProjectCommand {
  UpdateGroupPayloadCommand(this.registry, this.address, this.payload);

  final ProjectRegistry registry;
  final EntityAddress address;
  final Object? payload;

  Object? _previous;
  bool _captured = false;

  @override
  String get label => 'update group $address';

  @override
  Set<EntityAddress> get entitiesTouched => {address};

  @override
  void apply() {
    if (!_captured) {
      _previous = registry.groupAt(address)?.payload;
      _captured = true;
    }
    registry.updateGroupPayload(address, payload);
  }

  @override
  void revert() => registry.updateGroupPayload(address, _previous);

  @override
  Map<String, Object?> toJson() => {
    'type': 'update_group_payload',
    'address': address.format(),
    'payload': payload,
  };
}
