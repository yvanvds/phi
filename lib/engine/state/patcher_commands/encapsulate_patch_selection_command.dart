import 'dart:math' as math;
import 'dart:ui';

import '../../../design/widgets/patcher/patch_canvas_constants.dart';
import '../../../domain/patcher/patch_cable.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../domain/patcher/patch_node_id.dart';
import '../../../domain/patcher/patch_object_types.dart';
import '../../../domain/patcher/patch_port.dart';
import '../../../domain/patcher/patch_port_id.dart';
import '../../../domain/patcher/patch_port_kind.dart';
import '../../../domain/project/entity_address.dart';
import '../../../domain/project/project_command.dart';
import '../patch_node_spec.dart';
import '../patcher_controller.dart';

/// Moves a selection into a new `patcher` box at its place — Max's
/// *Encapsulate*, `Ctrl+Shift+E` (issue #552) — as one undoable step.
///
/// The selected nodes keep their logical ids, native handles and every cable
/// between them: the engine's containment is addressing, so they are only
/// marked as inside the new box ([PatcherController.setContainerPrimitive]).
/// A cable the selection's edge cut — one end selected, the other not, as the
/// window draws it — is routed through a new pin of the box instead:
///
/// - **into** the selection: one inlet per outside *source* pin (`~inlet` for
///   an audio cable, `.inlet` for a control one), so a source that fed three
///   selected objects feeds one box inlet that fans out to all three inside;
/// - **out of** it: one outlet per selected source pin, fanning out to every
///   outside target it reached.
///
/// Pins are numbered left to right by where the outside end of their cables
/// sits, so the box's pins line up with the cables reaching it. Inside, the
/// contents are moved to the window's top left, the inlets in a row above them
/// and the outlets in a row below.
///
/// The first [apply] works all of that out and records it; a **redo** replays
/// the record, bringing the box and its pins back under the *same* logical ids
/// so later commands that named them stay valid. [revert] takes it all apart
/// again: the selection back where it was, the box and its pins gone, the cut
/// cables re-wired.
class EncapsulatePatchSelectionCommand implements ProjectCommand {
  EncapsulatePatchSelectionCommand(this.controller, Set<PatchNodeId> ids)
    : ids = Set.unmodifiable(ids);

  final PatcherController controller;

  /// The selected nodes, all in one window and none a boundary object
  /// ([PatcherController.canEncapsulate]).
  final Set<PatchNodeId> ids;

  /// The window the selection sits in (null: the top level).
  PatchNodeId? _scope;

  PatchNodeId? _box;
  PatchNodeSpec? _boxSpec;

  /// The new inlet and outlet objects, in the order they were made.
  final List<PatchNodeId> _pins = [];
  final Map<PatchNodeId, PatchNodeSpec> _pinSpecs = {};

  /// Where each selected node was, and where it sits inside the box.
  final Map<PatchNodeId, Offset> _from = {};
  final Map<PatchNodeId, Offset> _to = {};

  /// The cables the selection's edge cut, and the ones wired through the new
  /// pins in their place.
  final List<PatchCable> _cut = [];
  final List<PatchCable> _wired = [];

  /// Space from the window's edge to the inlet row, and from the contents to
  /// the outlet row.
  static const double _margin = 2 * PatchCanvasConstants.gridCell;

  /// Space from the top of the inlet row to the top of the contents.
  static const double _rowGap = 3 * PatchCanvasConstants.gridCell;

  /// The new subpatch box, once applied.
  PatchNodeId? get boxId => _box;

  @override
  String get label => 'encapsulate ${ids.length} node(s)';

  @override
  Set<EntityAddress> get entitiesTouched => const {};

  @override
  void apply() {
    if (_box == null) {
      _firstApply();
    } else {
      _replay();
    }
    controller.selectNodes({_box!});
  }

  void _firstApply() {
    final c = controller;
    final scope = c.containerOf(ids.first);
    _scope = scope;
    final nodes = [for (final id in ids) c.graph.nodeById(id)!];

    // The cut cables, grouped by the real pin they leave from: one box pin
    // per group.
    final incoming = <PatchPortId, List<PatchCable>>{};
    final outgoing = <PatchPortId, List<PatchCable>>{};
    for (final cable in c.graph.cables) {
      final from = c.displayPort(cable.source).nodeId;
      final to = c.displayPort(cable.target).nodeId;
      if (c.containerOf(from) != scope) continue;
      final fromInside = ids.contains(from);
      final toInside = ids.contains(to);
      if (fromInside == toInside) continue;
      (toInside ? incoming : outgoing)
          .putIfAbsent(cable.source, () => [])
          .add(cable);
    }
    final inlets = incoming.entries.toList()
      ..sort(
        (a, b) => _compareAt(
          _outsideAt(a.value, source: true),
          _outsideAt(b.value, source: true),
          _tie(a.key, b.key),
        ),
      );
    final outlets = outgoing.entries.toList()
      ..sort(
        (a, b) => _compareAt(
          _outsideAt(a.value, source: false),
          _outsideAt(b.value, source: false),
          _tie(a.key, b.key),
        ),
      );

    for (final group in [...inlets, ...outlets]) {
      for (final cable in group.value) {
        c.removeCablePrimitive(cable);
        _cut.add(cable);
      }
    }

    // The box goes where the selection's top left corner was.
    final bounds = _boundsOf(nodes);
    final box = c.createObjectPrimitive(
      type: PatchObjectTypes.patcher,
      args: '',
      position: bounds.topLeft,
      container: scope,
    );
    _box = box.id;

    // Contents to the window's top left, below the row the inlets take.
    final shift =
        Offset(_margin, inlets.isEmpty ? _margin : _margin + _rowGap) -
        bounds.topLeft;
    for (final node in nodes) {
      _from[node.id] = node.position;
      _to[node.id] = node.position + shift;
      c
        ..setContainerPrimitive(node.id, box.id)
        ..placeNode(node.id, node.position + shift);
    }

    final inletRow = _layoutRow(
      inlets,
      y: _margin,
      makeType: (audio) =>
          audio ? PatchObjectTypes.dInlet : PatchObjectTypes.gInlet,
      insideXOf: (cables) => _minX(cables.map((k) => k.target)),
    );
    final outletRow = _layoutRow(
      outlets,
      y: bounds.bottom + shift.dy + _margin,
      makeType: (audio) =>
          audio ? PatchObjectTypes.dOutlet : PatchObjectTypes.gOutlet,
      insideXOf: (cables) => _minX(cables.map((k) => k.source)),
    );

    for (final (pin, group) in inletRow) {
      _wire(group.key, _port(pin, PatchPortSide.input));
      for (final cable in group.value) {
        _wire(_port(pin, PatchPortSide.output), cable.target);
      }
    }
    for (final (pin, group) in outletRow) {
      _wire(group.key, _port(pin, PatchPortSide.input));
      for (final cable in group.value) {
        _wire(_port(pin, PatchPortSide.output), cable.target);
      }
    }

    _boxSpec = c.captureSpec(box.id);
    for (final pin in _pins) {
      _pinSpecs[pin] = c.captureSpec(pin);
    }
  }

  /// Make one boundary object per group, numbered in order and laid out left
  /// to right at [y], each as near above (or below) the first selected node
  /// it reaches as the ones before it leave room for.
  List<(PatchNodeId, MapEntry<PatchPortId, List<PatchCable>>)> _layoutRow(
    List<MapEntry<PatchPortId, List<PatchCable>>> groups, {
    required double y,
    required String Function(bool audio) makeType,
    required double Function(List<PatchCable> cables) insideXOf,
  }) {
    final c = controller;
    final out = <(PatchNodeId, MapEntry<PatchPortId, List<PatchCable>>)>[];
    var nextFree = double.negativeInfinity;
    for (final (index, group) in groups.indexed) {
      final audio = group.value.first.kind == PatchPortKind.audio;
      final pin = c.createObjectPrimitive(
        type: makeType(audio),
        args: '$index',
        position: Offset(0, y),
        container: _box,
      );
      final x = math.max(insideXOf(group.value), nextFree);
      c.placeNode(pin.id, Offset(x, y));
      nextFree = x + pin.size.width + PatchCanvasConstants.gridCell;
      _pins.add(pin.id);
      out.add((pin.id, group));
    }
    return out;
  }

  /// The leftmost x, inside the box, of the selected nodes [ports] belong to
  /// (as drawn — a selected box's pin is on the box).
  double _minX(Iterable<PatchPortId> ports) {
    var x = double.infinity;
    for (final port in ports) {
      final id = controller.displayPort(port).nodeId;
      final at = _to[id];
      if (at != null) x = math.min(x, at.dx);
    }
    return x.isFinite ? x : _margin;
  }

  /// Where the outside end of a group's cables sits: the source node for an
  /// incoming group, the leftmost target node for an outgoing one.
  Offset _outsideAt(List<PatchCable> cables, {required bool source}) {
    Offset? best;
    for (final cable in cables) {
      final port = source ? cable.source : cable.target;
      final node = controller.graph.nodeById(
        controller.displayPort(port).nodeId,
      );
      final at = node?.position ?? Offset.zero;
      if (best == null || at.dx < best.dx) best = at;
    }
    return best ?? Offset.zero;
  }

  /// Same place: by node, then by pin, so the order never depends on how
  /// the sort happened to run.
  static int _tie(PatchPortId a, PatchPortId b) {
    final byNode = a.nodeId.value.compareTo(b.nodeId.value);
    return byNode != 0 ? byNode : a.index.compareTo(b.index);
  }

  static int _compareAt(Offset a, Offset b, int tie) {
    final byX = a.dx.compareTo(b.dx);
    if (byX != 0) return byX;
    final byY = a.dy.compareTo(b.dy);
    return byY != 0 ? byY : tie;
  }

  static Rect _boundsOf(List<PatchNode> nodes) => nodes
      .map((n) => n.position & n.size)
      .reduce((a, b) => a.expandToInclude(b));

  static PatchPortId _port(PatchNodeId id, PatchPortSide side) =>
      PatchPortId(nodeId: id, side: side, index: 0);

  void _wire(PatchPortId source, PatchPortId target) {
    final cable = controller.cableBetween(source, target);
    if (cable == null || _wired.contains(cable)) return;
    controller.addCablePrimitive(cable);
    _wired.add(cable);
  }

  void _replay() {
    final c = controller;
    for (final cable in _cut) {
      c.removeCablePrimitive(cable);
    }
    c.restoreNodePrimitive(_box!, _boxSpec!);
    for (final pin in _pins) {
      c.restoreNodePrimitive(pin, _pinSpecs[pin]!);
    }
    for (final id in ids) {
      c
        ..setContainerPrimitive(id, _box)
        ..placeNode(id, _to[id]!);
    }
    for (final cable in _wired) {
      c.addCablePrimitive(cable);
    }
  }

  @override
  void revert() {
    final c = controller;
    for (final cable in _wired) {
      c.removeCablePrimitive(cable);
    }
    for (final id in ids) {
      c
        ..setContainerPrimitive(id, _scope)
        ..placeNode(id, _from[id]!);
    }
    for (final pin in _pins.reversed) {
      c.deleteNodePrimitive(pin);
    }
    c.deleteNodePrimitive(_box!);
    for (final cable in _cut) {
      c.addCablePrimitive(cable);
    }
    c.selectNodes(ids);
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'patch_encapsulate',
    'nodes': ids.length,
  };
}
