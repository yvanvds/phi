import '../../domain/patcher/patch_boundary.dart';
import '../../domain/patcher/patch_cable.dart';
import '../../domain/patcher/patch_node.dart';
import '../../domain/patcher/patch_node_id.dart';
import '../../domain/patcher/patch_port.dart';
import '../../domain/patcher/patch_port_id.dart';
import 'patcher_controller.dart';

/// Makes one window of a patch hold what another window holds (issue #553,
/// design `docs/design/patcher.md` §13): the contents of an abstraction's
/// instance box follow its definition, and *make abstraction* copies a box's
/// contents out into a new definition.
///
/// The engine keeps a subpatch's contents in the parent's flat graph, so an
/// instance is a copy. It is reconciled rather than thrown away and rebuilt, so
/// that changing one argument of a definition does not cost every instance its
/// delay lines, its live GUI values and its saved object state. Objects are
/// paired up, window by window, from the surest match to the loosest:
///
/// 1. same type, arguments and position: nothing to do;
/// 2. same type and arguments: it moved;
/// 3. same type and position: its arguments changed.
///
/// What pairs up keeps its logical id, its native object and every cable the
/// definition still has; the rest is deleted or created. A wrong pairing of two
/// look-alike objects costs state at worst: the wiring is compared afterwards,
/// so the result always has the definition's objects and cables.
///
/// **The parent's cables.** A cable the parent wired to the box hangs off a
/// boundary object inside it, so it stays with that object when it is paired up.
/// When the object goes (a `.inlet` retyped to `~inlet`, say), the cable is
/// wired to whichever boundary object now claims the same pin, if the types
/// still accept each other; otherwise it is dropped, and [dropped] counts it so
/// the canvas can say so.
///
/// Everything here is a direct primitive, not a journaled command: this is the
/// consequence of an edit that was journaled somewhere else, in the definition.
class PatchInstanceMaterialiser {
  PatchInstanceMaterialiser({
    required this.source,
    required this.sourceScope,
    required this.target,
    required this.targetScope,
  });

  /// The editor holding the contents to copy.
  final PatcherController source;

  /// The window of [source] to copy: a box, or null for the patch's top level.
  final PatchNodeId? sourceScope;

  /// The editor to bring in line.
  final PatcherController target;

  /// The window of [target] to bring in line.
  final PatchNodeId? targetScope;

  /// Each object of [source] and the object of [target] that is its copy.
  final Map<PatchNodeId, PatchNodeId> _copyOf = {};

  /// Objects of [source] with no counterpart yet, containers before contents.
  final List<PatchNodeId> _missing = [];

  /// Objects of [target] with no counterpart: each goes with what it holds.
  final List<PatchNodeId> _doomed = [];

  /// Whether the last [run] touched [target] at all.
  bool changed = false;

  /// How many of the parent's cables the last [run] could not carry.
  int dropped = 0;

  /// Reconcile [targetScope] with [sourceScope]. Writes nothing when they
  /// already agree, so it is cheap to run after any edit.
  void run() {
    _pair(sourceScope, targetScope);
    final orphans = _unwireDoomed();
    _createMissing();
    final wanted = _wantedCables();
    _removeUnwantedCables(wanted);
    for (final root in _doomed) {
      target.deleteNodePrimitive(root);
      changed = true;
    }
    _updatePaired();
    _addWantedCables(wanted);
    _rewire(orphans);
  }

  // ─── pairing ─────────────────────────────────────────────────────────

  void _pair(PatchNodeId? from, PatchNodeId? into) {
    final wants = source.nodesIn(from).toList();
    final has = target.nodesIn(into).toList();
    final pairs = <(PatchNode, PatchNode)>[];

    void pairWhere(bool Function(PatchNode want, PatchNode have) same) {
      for (final want in wants.toList()) {
        for (final have in has) {
          if (!same(want, have)) continue;
          pairs.add((want, have));
          wants.remove(want);
          has.remove(have);
          break;
        }
      }
    }

    bool sameType(PatchNode a, PatchNode b) => a.type == b.type;
    bool sameArgs(PatchNode a, PatchNode b) =>
        source.argsOf(a.id) == target.argsOf(b.id);
    bool samePlace(PatchNode a, PatchNode b) => a.position == b.position;
    pairWhere((a, b) => sameType(a, b) && sameArgs(a, b) && samePlace(a, b));
    pairWhere((a, b) => sameType(a, b) && sameArgs(a, b));
    pairWhere((a, b) => sameType(a, b) && samePlace(a, b));

    _missing.addAll(source.subtreeOf(wants.map((n) => n.id)));
    _doomed.addAll(has.map((n) => n.id));
    for (final (want, have) in pairs) {
      _copyOf[want.id] = have.id;
      if (PatchBoundary.isSubpatch(want.type)) _pair(want.id, have.id);
    }
  }

  // ─── the objects ─────────────────────────────────────────────────────

  /// Take every cable off the objects about to go. The ones that came from the
  /// parent are returned, to be wired again once the new pins exist.
  List<_OrphanedCable> _unwireDoomed() {
    if (_doomed.isEmpty) return const [];
    final doomed = target.subtreeOf(_doomed).toSet();
    final orphans = <_OrphanedCable>[];
    for (final cable in target.cablesTouching(doomed)) {
      target.removeCablePrimitive(cable);
      changed = true;
      final pin = _pinOf(cable);
      if (pin != null && doomed.contains(pin.nodeId)) {
        orphans.add(_OrphanedCable(cable, pin, _pinIndex(pin.nodeId)));
      }
    }
    return orphans;
  }

  /// The end of [cable] that is a parent-facing pin of a boundary object
  /// directly in the window being reconciled, if it has one.
  PatchPortId? _pinOf(PatchCable cable) {
    final box = targetScope;
    if (box == null) return null;
    for (final end in [cable.source, cable.target]) {
      final node = target.graph.nodeById(end.nodeId);
      if (node == null || node.container != box) continue;
      if (PatchBoundary.isParentFacing(node.type, end.side, end.index)) {
        return end;
      }
    }
    return null;
  }

  int _pinIndex(PatchNodeId boundary) =>
      PatchBoundary.indexOf(target.argsOf(boundary));

  void _createMissing() {
    for (final id in _missing) {
      final container = source.containerOf(id);
      final into = container == sourceScope ? targetScope : _copyOf[container];
      _copyOf[id] = target.createNodePrimitive(
        source.captureSpec(id).inContainer(into),
      );
      changed = true;
    }
  }

  /// Bring every paired object's arguments, position and decoration in line.
  void _updatePaired() {
    final created = _missing.toSet();
    _copyOf.forEach((from, to) {
      if (created.contains(from)) return;
      final want = source.captureSpec(from);
      if (target.argsOf(to) != want.args) {
        // A cable a shrunken object lost is either the definition's, re-wired
        // below if it still stands, or the parent's, and that one is gone.
        final lost = target.setNodeParams(to, want.args);
        dropped += lost.where(_isFromParent).length;
        changed = true;
      }
      if (target.graph.nodeById(to)?.position != want.position) {
        target.placeNode(to, want.position);
        changed = true;
      }
      final have = target.captureSpec(to).gui;
      for (final key in {...want.gui.keys, ...have.keys}) {
        final value = want.gui[key] ?? '';
        if ((have[key] ?? '') == value) continue;
        target.setGuiPropertyPrimitive(to, key, value);
        changed = true;
      }
    });
  }

  bool _isFromParent(PatchCable cable) {
    final inside = _insideTarget();
    return !inside.contains(cable.source.nodeId) ||
        !inside.contains(cable.target.nodeId);
  }

  /// Everything now in the window being reconciled, at any depth.
  Set<PatchNodeId> _insideTarget() =>
      target.subtreeOf(target.nodesIn(targetScope).map((n) => n.id)).toSet();

  // ─── the cables ──────────────────────────────────────────────────────

  /// The [source] cables inside the copied window, in terms of their copies.
  List<(PatchPortId, PatchPortId)> _wantedCables() {
    final inside = source
        .subtreeOf(source.nodesIn(sourceScope).map((n) => n.id))
        .toSet();
    return [
      for (final cable in source.cablesWithin(inside))
        (_copied(cable.source), _copied(cable.target)),
    ];
  }

  PatchPortId _copied(PatchPortId port) => PatchPortId(
    nodeId: _copyOf[port.nodeId]!,
    side: port.side,
    index: port.index,
  );

  void _removeUnwantedCables(List<(PatchPortId, PatchPortId)> wanted) {
    final keep = wanted.toSet();
    for (final cable in target.cablesWithin(_insideTarget())) {
      if (keep.contains((cable.source, cable.target))) continue;
      target.removeCablePrimitive(cable);
      changed = true;
    }
  }

  void _addWantedCables(List<(PatchPortId, PatchPortId)> wanted) {
    final have = {
      for (final cable in target.graph.cables) (cable.source, cable.target),
    };
    for (final pair in wanted) {
      if (have.contains(pair)) continue;
      final cable = target.cableBetween(pair.$1, pair.$2);
      if (cable == null) continue;
      target.addCablePrimitive(cable);
      changed = true;
    }
  }

  /// Wire each orphan to the boundary object that now claims its pin, or count
  /// it as dropped when none does or the types no longer accept each other.
  void _rewire(List<_OrphanedCable> orphans) {
    final box = targetScope;
    if (box == null) return;
    for (final orphan in orphans) {
      final old = orphan.cable;
      final pin = PatchPortId(
        nodeId: box,
        side: orphan.end.side,
        index: orphan.pin,
      );
      final isInlet = orphan.end.side == PatchPortSide.input;
      final from = isInlet ? old.source : pin;
      final to = isInlet ? pin : old.target;
      final cable = target.canConnect(from, to)
          ? target.cableBetween(from, to)
          : null;
      if (cable == null) {
        dropped++;
      } else {
        target.addCablePrimitive(cable);
      }
    }
  }
}

/// A cable the parent wired to a boundary object that is going away: the
/// parent-facing [end] it was on, and the box [pin] that object claimed.
class _OrphanedCable {
  const _OrphanedCable(this.cable, this.end, this.pin);

  final PatchCable cable;
  final PatchPortId end;
  final int pin;
}
