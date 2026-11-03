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
    List<int?>? containers,
  }) : nodes = List.unmodifiable(nodes),
       cables = List.unmodifiable(cables),
       containers = List.unmodifiable(
         containers ?? List<int?>.filled(nodes.length, null),
       ),
       assert(containers == null || containers.length == nodes.length);

  final List<PatchNodeSpec> nodes;

  /// Per entry of [nodes], the index of the copied subpatch box it sits
  /// inside, or null for an object of the copied selection itself — which a
  /// paste puts in the window it lands in (issue #481). A box's contents
  /// always come after the box.
  final List<int?> containers;
  final List<PatchClipboardCable> cables;

  bool get isEmpty => nodes.isEmpty;
}
