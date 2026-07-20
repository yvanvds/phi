import '../../project/entity_address.dart';
import '../../project/project_command.dart';
import '../patch_connection.dart';
import '../patch_edit_gateway.dart';

/// Wires one cable into the patch at [patchAddress] — the *connect* gesture
/// (design `docs/design/patcher.md` §3, §6).
///
/// [apply] forwards the [connection] to the [gateway]; [revert] disconnects it.
class ConnectCommand implements ProjectCommand {
  /// Wires [connection] into the patch at [patchAddress] through [gateway].
  ConnectCommand(this.gateway, this.patchAddress, this.connection);

  /// The seam the gesture is forwarded through.
  final PatchEditGateway gateway;

  /// The `patch.` entity being edited — dirtied so save re-dumps it.
  final EntityAddress patchAddress;

  /// The cable to wire.
  final PatchConnection connection;

  @override
  String get label => 'connect';

  @override
  Set<EntityAddress> get entitiesTouched => {patchAddress};

  @override
  void apply() => gateway.connect(connection);

  @override
  void revert() => gateway.disconnect(connection);

  @override
  Map<String, Object?> toJson() => {
    'type': 'connect',
    'patch': patchAddress.format(),
    ...connection.toJson(),
  };
}
