import '../../domain/patcher/patch_port_kind.dart';

/// Topology of a freshly-created patcher object as the gateway reports it.
///
/// `inputKinds.length == inputs`, `outputKinds.length == outputs`. Used by
/// [PatcherController] to build the [PatchPort] lists for a [PatchNode].
class PatcherNodeSnapshot {
  const PatcherNodeSnapshot({
    required this.inputs,
    required this.outputs,
    required this.inputKinds,
    required this.outputKinds,
  });

  final int inputs;
  final int outputs;
  final List<PatchPortKind> inputKinds;
  final List<PatchPortKind> outputKinds;
}
