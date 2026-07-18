import '../entity_address.dart';
import '../project_command.dart';
import '../project_registry.dart';

/// Replaces the payload of the entity at [address] with [payload] — the
/// registry command behind clip-edit persistence (issue #135).
///
/// A clip edit mutates the live clip and then publishes a fresh snapshot of the
/// clip's whole interpretation as the `clip.` entity's new payload; this command
/// carries that snapshot so the change is dirty-tracked and journaled like any
/// other. [apply] captures the previous payload so [revert] restores it exactly,
/// and [toJson] carries the new payload verbatim (already JSON — the journal
/// contract) so a forward replay reproduces the update.
class UpdateEntityPayloadCommand implements ProjectCommand {
  UpdateEntityPayloadCommand(this.registry, this.address, this.payload);

  final ProjectRegistry registry;
  final EntityAddress address;
  final Object? payload;

  Object? _previous;
  bool _captured = false;

  @override
  String get label => 'update $address';

  @override
  Set<EntityAddress> get entitiesTouched => {address};

  @override
  void apply() {
    if (!_captured) {
      _previous = registry.entityAt(address)?.payload;
      _captured = true;
    }
    registry.updateEntityPayload(address, payload);
  }

  @override
  void revert() => registry.updateEntityPayload(address, _previous);

  @override
  Map<String, Object?> toJson() => {
    'type': 'update_payload',
    'address': address.format(),
    'payload': payload,
  };
}
