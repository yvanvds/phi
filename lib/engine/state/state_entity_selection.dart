import '../../domain/project/entity_address.dart';
import '../../domain/runtime/runtime_variable_registry.dart';
import 'state_machine_controller.dart';

/// The cross-surface selection value the State canvas publishes into
/// `SessionState.selection` when a node is tapped (issue #241): the selected
/// `state.` entity plus the controller that fronts it, so the right
/// inspector can resolve the live node, rename it through the journaled
/// refactor path, and follow the controller's notifications.
class StateEntitySelection {
  const StateEntitySelection({
    required this.controller,
    required this.address,
    this.variables,
  });

  /// The registry-backed state machine the selected entity lives in.
  final StateMachineController controller;

  /// The selected `state.` entity.
  final EntityAddress address;

  /// The runtime-variable registry the inspector's trigger editor offers
  /// definitions from (issue #245). `null` — a bare setup — leaves the
  /// variable picker empty.
  final RuntimeVariableRegistry? variables;

  /// The same selection pointed at [address] — what the inspector publishes
  /// after driving a rename, so the selection follows the new address.
  StateEntitySelection withAddress(EntityAddress address) =>
      StateEntitySelection(
        controller: controller,
        address: address,
        variables: variables,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StateEntitySelection &&
          identical(other.controller, controller) &&
          other.address == address &&
          identical(other.variables, variables);

  @override
  int get hashCode => Object.hash(
    identityHashCode(controller),
    address,
    identityHashCode(variables),
  );
}
