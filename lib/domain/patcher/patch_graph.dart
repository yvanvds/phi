import 'package:flutter/foundation.dart';

import 'patch_cable.dart';
import 'patch_node.dart';
import 'patch_node_id.dart';
import 'patch_port_id.dart';

/// The dart-side mirror of a native patcher's topology, plus the canvas
/// state the native side knows nothing about (in-flight cable drag,
/// future selection).
///
/// Notifies on graph-level changes — add/remove node, add/remove cable,
/// drag-state toggles. Per-node mutable state (position, armed) fires
/// on the [PatchNode] itself, matching the [MixerChannel] split.
///
/// [version] bumps on every notify so the cable painter's
/// `shouldRepaint` can do a cheap int comparison.
class PatchGraph extends ChangeNotifier {
  final Map<PatchNodeId, PatchNode> _nodes = {};
  final List<PatchCable> _cables = [];
  PatchPortId? _dragSourcePort;
  int _version = 0;

  /// Monotonic counter — bumped on every change.
  int get version => _version;

  /// All nodes in insertion order is intentionally not guaranteed; widgets
  /// should treat this as a set.
  Iterable<PatchNode> get nodes => _nodes.values;

  List<PatchCable> get cables => List.unmodifiable(_cables);

  /// The port currently being dragged from, if any.
  PatchPortId? get dragSourcePort => _dragSourcePort;

  PatchNode? nodeById(PatchNodeId id) => _nodes[id];

  void addNode(PatchNode node) {
    _nodes[node.id] = node;
    _bumpAndNotify();
  }

  /// Remove a node and any cables touching it.
  void removeNode(PatchNodeId id) {
    if (_nodes.remove(id) == null) return;
    _cables.removeWhere((c) => c.source.nodeId == id || c.target.nodeId == id);
    _bumpAndNotify();
  }

  void addCable(PatchCable cable) {
    _cables.add(cable);
    _bumpAndNotify();
  }

  void removeCable(PatchCable cable) {
    if (!_cables.remove(cable)) return;
    _bumpAndNotify();
  }

  /// Start a drag-to-create-cable gesture from [from] (must be an output).
  void beginCableDrag(PatchPortId from) {
    _dragSourcePort = from;
    _bumpAndNotify();
  }

  /// End the in-flight cable drag, whether or not it landed on a target.
  void endCableDrag() {
    if (_dragSourcePort == null) return;
    _dragSourcePort = null;
    _bumpAndNotify();
  }

  void _bumpAndNotify() {
    _version++;
    notifyListeners();
  }
}
