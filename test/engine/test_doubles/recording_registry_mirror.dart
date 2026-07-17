import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/engine/bridge/registry_mirror.dart';

/// A [RegistryMirror] test double that records every notification it receives,
/// so tests can assert which registry lifecycle events reached the mirror.
class RecordingRegistryMirror implements RegistryMirror {
  final List<EntityAddress> creates = [];
  final List<EntityAddress> deletes = [];
  final List<(EntityAddress, EntityAddress)> renames = [];
  final List<(EntityAddress, EntityAddress)> regroups = [];

  @override
  void onCreate(EntityAddress address) => creates.add(address);

  @override
  void onDelete(EntityAddress address) => deletes.add(address);

  @override
  void onRename(EntityAddress from, EntityAddress to) =>
      renames.add((from, to));

  @override
  void onRegroup(EntityAddress from, EntityAddress to) =>
      regroups.add((from, to));
}
