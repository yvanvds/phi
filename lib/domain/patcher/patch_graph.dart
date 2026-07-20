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
  Set<PatchNodeId> _selectedNodes = const {};
  PatchCable? _selectedCable;
  int _version = 0;

  /// Monotonic counter — bumped on every change.
  int get version => _version;

  /// All nodes in insertion order is intentionally not guaranteed; widgets
  /// should treat this as a set.
  Iterable<PatchNode> get nodes => _nodes.values;

  List<PatchCable> get cables => List.unmodifiable(_cables);

  /// The port currently being dragged from, if any.
  PatchPortId? get dragSourcePort => _dragSourcePort;

  /// The set of currently-selected nodes (click / shift-click / marquee).
  /// A node and a cable are never selected at once — selecting one clears the
  /// other.
  Set<PatchNodeId> get selectedNodes => Set.unmodifiable(_selectedNodes);

  bool isNodeSelected(PatchNodeId id) => _selectedNodes.contains(id);

  /// The single selected cable, or null. Selecting a cable clears the node
  /// selection (and vice versa).
  PatchCable? get selectedCable => _selectedCable;

  PatchNode? nodeById(PatchNodeId id) => _nodes[id];

  void addNode(PatchNode node) {
    _nodes[node.id] = node;
    _bumpAndNotify();
  }

  /// Remove a node and any cables touching it.
  void removeNode(PatchNodeId id) {
    if (_nodes.remove(id) == null) return;
    _cables.removeWhere((c) => c.source.nodeId == id || c.target.nodeId == id);
    if (_selectedNodes.contains(id)) {
      _selectedNodes = _selectedNodes.where((n) => n != id).toSet();
    }
    final selected = _selectedCable;
    if (selected != null &&
        (selected.source.nodeId == id || selected.target.nodeId == id)) {
      _selectedCable = null;
    }
    _bumpAndNotify();
  }

  void addCable(PatchCable cable) {
    _cables.add(cable);
    _bumpAndNotify();
  }

  void removeCable(PatchCable cable) {
    if (!_cables.remove(cable)) return;
    if (_selectedCable == cable) _selectedCable = null;
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

  // ─── selection (canvas-only, native side unaware) ────────────────────

  /// Replace the node selection wholesale, clearing any cable selection.
  void selectNodes(Set<PatchNodeId> ids) {
    final next = Set<PatchNodeId>.of(ids);
    if (_selectedCable == null && setEquals(_selectedNodes, next)) return;
    _selectedNodes = next;
    _selectedCable = null;
    _bumpAndNotify();
  }

  /// Toggle one node's membership in the selection (shift-click), clearing any
  /// cable selection.
  void toggleNode(PatchNodeId id) {
    final next = Set<PatchNodeId>.of(_selectedNodes);
    next.contains(id) ? next.remove(id) : next.add(id);
    selectNodes(next);
  }

  /// Select a single cable, clearing any node selection.
  void selectCable(PatchCable cable) {
    if (_selectedCable == cable && _selectedNodes.isEmpty) return;
    _selectedCable = cable;
    _selectedNodes = const {};
    _bumpAndNotify();
  }

  /// Clear every selection (nodes and cable).
  void clearSelection() {
    if (_selectedNodes.isEmpty && _selectedCable == null) return;
    _selectedNodes = const {};
    _selectedCable = null;
    _bumpAndNotify();
  }

  void _bumpAndNotify() {
    _version++;
    notifyListeners();
  }
}
