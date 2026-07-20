import '../../project/entity_address.dart';
import '../../project/project_command.dart';
import '../patch_connection.dart';
import '../patch_edit_gateway.dart';

/// Removes one cable from the patch at [patchAddress] — the *disconnect* gesture
/// (design `docs/design/patcher.md` §3, §6).
///
/// [apply] forwards the disconnect to the [gateway]; [revert] re-wires the
/// [connection] — the exact inverse of [ConnectCommand].
class DisconnectCommand implements ProjectCommand {
  /// Removes [connection] from the patch at [patchAddress] through [gateway].
  DisconnectCommand(this.gateway, this.patchAddress, this.connection);

  /// The seam the gesture is forwarded through.
  final PatchEditGateway gateway;

  /// The `patch.` entity being edited — dirtied so save re-dumps it.
  final EntityAddress patchAddress;

  /// The cable to remove.
  final PatchConnection connection;

  @override
  String get label => 'disconnect';

  @override
  Set<EntityAddress> get entitiesTouched => {patchAddress};

  @override
  void apply() => gateway.disconnect(connection);

  @override
  void revert() => gateway.connect(connection);

  @override
  Map<String, Object?> toJson() => {
    'type': 'disconnect',
    'patch': patchAddress.format(),
    ...connection.toJson(),
  };
}
