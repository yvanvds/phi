import 'dart:ui';

import '../../../domain/patcher/patch_boundary.dart';
import '../../../domain/patcher/patch_cable.dart';
import '../../../domain/patcher/patch_node_id.dart';
import '../../../domain/patcher/patch_port.dart';
import '../../../domain/patcher/patch_port_id.dart';
import '../../../domain/project/entity_address.dart';
import '../../../domain/project/project_command.dart';
import '../patch_node_spec.dart';
import '../patcher_controller.dart';

/// Unpacks subpatch boxes into the window they sit in — *De-encapsulate*,
/// `Ctrl+Shift+D` (issue #552), the reverse of
/// `EncapsulatePatchSelectionCommand` — as one undoable step.
///
/// For each box, everything inside it except its inlet and outlet objects
/// moves out, keeping its logical id, native handle and cables, and lands
/// where the box was (the contents' top left corner on the box's). The inlet
/// and outlet objects go, and with them the box: every cable that ran through
/// one — from the parent into an inlet and on from the inlet inside, or out of
/// an outlet the same way — is wired straight from where it came from to where
/// it went, following a pin wired straight to another pin through as well.
///
/// The first [apply] works that out and records it per box; a **redo** replays
/// the record. [revert] puts every box back under its own logical id, with its
/// pins and their cables, and the contents back inside.
class DeencapsulatePatchSubpatchesCommand implements ProjectCommand {
  DeencapsulatePatchSubpatchesCommand(this.controller, Set<PatchNodeId> boxes)
    : boxes = Set.unmodifiable(boxes);

  final PatcherController controller;

  /// The subpatch boxes to unpack, all in one window.
  final Set<PatchNodeId> boxes;

  /// What unpacking each box did, in the order it was done.
  final List<_Unpacked> _done = [];
  bool _applied = false;

  @override
  String get label => 'de-encapsulate ${boxes.length} subpatch(es)';

  @override
  Set<EntityAddress> get entitiesTouched => const {};

  @override
  void apply() {
    if (!_applied) {
      // Sorted so a redo of a recorded run and the first run agree on order.
      final order = boxes.toList()..sort((a, b) => a.value - b.value);
      for (final box in order) {
        final unpacked = _unpack(box);
        if (unpacked != null) _done.add(unpacked);
      }
      _applied = true;
    } else {
      for (final unpacked in _done) {
        _replay(unpacked);
      }
    }
    controller.selectNodes({for (final u in _done) ...u.contents});
  }

  _Unpacked? _unpack(PatchNodeId box) {
    final c = controller;
    final boxNode = c.graph.nodeById(box);
    if (boxNode == null || !c.isSubpatch(box)) return null;
    final inside = c.nodesIn(box).toList();
    final pins = [
      for (final n in inside)
        if (PatchBoundary.isBoundary(n.type)) n.id,
    ];
    final contents = [
      for (final n in inside)
        if (!PatchBoundary.isBoundary(n.type)) n.id,
    ];
    final relays = pins.toSet();

    // Every path through the pins: from a real source into a pin, through any
    // number of pins wired straight to each other, out to a real target.
    final through = <(PatchPortId, PatchPortId)>[];
    void follow(PatchNodeId relay, PatchPortId source, Set<PatchNodeId> seen) {
      for (final cable in c.graph.cables) {
        if (cable.source != _port(relay, PatchPortSide.output)) continue;
        final next = cable.target.nodeId;
        if (relays.contains(next)) {
          if (cable.target.index == 0 && seen.add(next)) {
            follow(next, source, seen);
          }
          continue;
        }
        through.add((source, cable.target));
      }
    }

    for (final cable in c.graph.cables) {
      if (relays.contains(cable.source.nodeId)) continue;
      final relay = cable.target.nodeId;
      if (!relays.contains(relay) || cable.target.index != 0) continue;
      follow(relay, cable.source, {relay});
    }

    final cut = c.cablesTouching(relays);
    final unpacked = _Unpacked(
      box: box,
      boxSpec: c.captureSpec(box),
      scope: boxNode.container,
      pins: pins,
      pinSpecs: {for (final p in pins) p: c.captureSpec(p)},
      contents: contents,
      cut: cut,
    );

    for (final cable in cut) {
      c.removeCablePrimitive(cable);
    }
    for (final pin in pins.reversed) {
      c.deleteNodePrimitive(pin);
    }
    final shift = contents.isEmpty
        ? Offset.zero
        : boxNode.position - _topLeftOf(contents);
    for (final id in contents) {
      final at = c.graph.nodeById(id)!.position;
      unpacked.from[id] = at;
      unpacked.to[id] = at + shift;
      c
        ..setContainerPrimitive(id, unpacked.scope)
        ..placeNode(id, at + shift);
    }
    c.deleteNodePrimitive(box);
    for (final (source, target) in through) {
      final cable = c.cableBetween(source, target);
      if (cable == null) continue;
      if (c.graph.cables.contains(cable)) continue;
      c.addCablePrimitive(cable);
      unpacked.wired.add(cable);
    }
    return unpacked;
  }

  void _replay(_Unpacked u) {
    final c = controller;
    for (final cable in u.cut) {
      c.removeCablePrimitive(cable);
    }
    for (final pin in u.pins.reversed) {
      c.deleteNodePrimitive(pin);
    }
    for (final id in u.contents) {
      c
        ..setContainerPrimitive(id, u.scope)
        ..placeNode(id, u.to[id]!);
    }
    c.deleteNodePrimitive(u.box);
    for (final cable in u.wired) {
      c.addCablePrimitive(cable);
    }
  }

  @override
  void revert() {
    final c = controller;
    for (final u in _done.reversed) {
      for (final cable in u.wired) {
        c.removeCablePrimitive(cable);
      }
      c.restoreNodePrimitive(u.box, u.boxSpec);
      for (final id in u.contents) {
        c
          ..setContainerPrimitive(id, u.box)
          ..placeNode(id, u.from[id]!);
      }
      for (final pin in u.pins) {
        c.restoreNodePrimitive(pin, u.pinSpecs[pin]!);
      }
      for (final cable in u.cut) {
        c.addCablePrimitive(cable);
      }
    }
    c.selectNodes(boxes);
  }

  Offset _topLeftOf(List<PatchNodeId> ids) {
    var x = double.infinity;
    var y = double.infinity;
    for (final id in ids) {
      final at = controller.graph.nodeById(id)!.position;
      if (at.dx < x) x = at.dx;
      if (at.dy < y) y = at.dy;
    }
    return Offset(x, y);
  }

  static PatchPortId _port(PatchNodeId id, PatchPortSide side) =>
      PatchPortId(nodeId: id, side: side, index: 0);

  @override
  Map<String, Object?> toJson() => {
    'type': 'patch_deencapsulate',
    'subpatches': boxes.length,
  };
}

/// What de-encapsulating one box did — enough to replay it and to undo it.
class _Unpacked {
  _Unpacked({
    required this.box,
    required this.boxSpec,
    required this.scope,
    required this.pins,
    required this.pinSpecs,
    required this.contents,
    required this.cut,
  });

  final PatchNodeId box;
  final PatchNodeSpec boxSpec;
  final PatchNodeId? scope;
  final List<PatchNodeId> pins;
  final Map<PatchNodeId, PatchNodeSpec> pinSpecs;
  final List<PatchNodeId> contents;
  final List<PatchCable> cut;
  final Map<PatchNodeId, Offset> from = {};
  final Map<PatchNodeId, Offset> to = {};
  final List<PatchCable> wired = [];
}
