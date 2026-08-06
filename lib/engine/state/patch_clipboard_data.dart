import 'patch_clipboard_cable.dart';
import 'patch_node_spec.dart';

/// One copied selection — a self-contained graph fragment.
///
/// [nodes] are full [PatchNodeSpec]s (type · args · position · size · ports),
/// so a paste can recreate each object without the originals still existing;
/// [cables] are the intra-selection connections, endpoints as indices into
/// [nodes] (see [PatchClipboardCable]). Immutable: a paste never mutates what
/// was copied, so the same copy pastes identically any number of times.
class PatchClipboardData {
  PatchClipboardData({
    required List<PatchNodeSpec> nodes,
    required List<PatchClipboardCable> cables,
  }) : nodes = List.unmodifiable(nodes),
       cables = List.unmodifiable(cables);

  final List<PatchNodeSpec> nodes;
  final List<PatchClipboardCable> cables;

  bool get isEmpty => nodes.isEmpty;
}
