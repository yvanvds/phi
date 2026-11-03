import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_cable.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:yse/yse.dart';

import '../test_doubles/fake_patcher_gateway.dart';

/// Subpatches in the editor (issue #481): a `patcher` box whose contents are
/// ordinary objects of the same native patcher, marked as inside it, and whose
/// pins are the boundary objects among them.
void main() {
  late FakePatcherGateway gateway;
  late PatcherController controller;

  PatchObjectDescriptor desc(String type) =>
      gateway.objectTypes().firstWhere((d) => d.type == type);

  PatchNodeId make(
    String type, {
    String args = '',
    PatchNodeId? inside,
    Offset at = Offset.zero,
  }) => controller.createObject(
    desc: desc(type),
    position: at,
    args: args,
    container: inside,
  )!;

  PatchPortId inlet(PatchNodeId id, [int i = 0]) =>
      PatchPortId(nodeId: id, side: PatchPortSide.input, index: i);
  PatchPortId outlet(PatchNodeId id, [int i = 0]) =>
      PatchPortId(nodeId: id, side: PatchPortSide.output, index: i);

  int nativeOf(PatchNodeId id) => id.value;

  setUp(() {
    gateway = FakePatcherGateway();
    controller = PatcherController(gateway);
  });

  tearDown(() => controller.dispose());

  /// A `patcher gain` box holding `~inlet 0` → `~sine` → `~outlet 0`.
  ({PatchNodeId box, PatchNodeId inlet, PatchNodeId sine, PatchNodeId outlet})
  gainBox() {
    final box = make(Obj.patcher, args: 'gain', at: const Offset(100, 100));
    final i = make(Obj.dInlet, args: '0', inside: box);
    final s = make(Obj.dSine, args: '440', inside: box);
    final o = make(Obj.dOutlet, args: '0', inside: box);
    controller
      ..connectViaGesture(outlet(i), inlet(s))
      ..connectViaGesture(outlet(s), inlet(o));
    return (box: box, inlet: i, sine: s, outlet: o);
  }

  group('contents and pins', () {
    test('an object made inside a box is put inside it, natively too', () {
      final box = make(Obj.patcher, args: 'gain');
      final s = make(Obj.dSine, args: '440', inside: box);

      expect(controller.containerOf(s), box);
      expect(controller.nodesIn(null).map((n) => n.id), [box]);
      expect(controller.nodesIn(box).map((n) => n.id), [s]);
      expect(
        gateway.calls,
        contains('setContainer:${nativeOf(s)}:${nativeOf(box)}'),
      );
      expect(
        gateway.instances.values.single.nodes[nativeOf(s)]!.container,
        nativeOf(box),
      );
    });

    test('boundary objects give the box its pins, kinds and all', () {
      final box = make(Obj.patcher);
      final node = controller.graph.nodeById(box)!;
      expect(node.inputs, isEmpty);
      expect(node.outputs, isEmpty);

      make(Obj.dInlet, args: '0', inside: box);
      make(Obj.gInlet, args: '1', inside: box);
      make(Obj.dOutlet, args: '0', inside: box);

      expect(node.inputs.map((p) => p.kind), [
        PatchPortKind.audio,
        PatchPortKind.control,
      ]);
      expect(node.outputs.map((p) => p.kind), [PatchPortKind.audio]);
    });

    test('a parent-facing pin is hidden; the inside one is not', () {
      final g = gainBox();
      expect(controller.isPortVisible(inlet(g.inlet)), isFalse);
      expect(controller.isPortVisible(outlet(g.inlet)), isTrue);
      expect(controller.isPortVisible(outlet(g.outlet)), isFalse);
      expect(controller.isPortVisible(inlet(g.outlet)), isTrue);
    });

    test('scopeTitle names the path from the top, unnamed as patcher', () {
      final outer = make(Obj.patcher, args: 'fx');
      final inner = make(Obj.patcher, inside: outer);
      expect(controller.scopeTitle(null), '');
      expect(controller.scopeTitle(outer), 'fx');
      expect(controller.scopeTitle(inner), 'fx › patcher');
    });
  });

  group('wiring through the box', () {
    test('a cable to a box pin lands on the boundary object behind it', () {
      final g = gainBox();
      final src = make(Obj.dSine, args: '220');
      final dac = make(Obj.dDac);

      expect(controller.connectViaGesture(outlet(src), inlet(g.box)), isTrue);
      expect(controller.connectViaGesture(outlet(g.box), inlet(dac)), isTrue);

      final into = controller.graph.cables.firstWhere(
        (c) => c.source == outlet(src),
      );
      expect(into.target, inlet(g.inlet), reason: 'as the engine records it');
      expect(controller.displayPort(into.target), inlet(g.box));
      final out = controller.graph.cables.firstWhere(
        (c) => c.target == inlet(dac),
      );
      expect(out.source, outlet(g.outlet));
      expect(controller.displayPort(out.source), outlet(g.box));
      expect(
        gateway.cables.map(
          (c) => '${c.fromHandleId}:${c.outlet}->${c.toHandleId}:${c.inlet}',
        ),
        containsAll([
          '${nativeOf(src)}:0->${nativeOf(g.inlet)}:0',
          '${nativeOf(g.outlet)}:0->${nativeOf(dac)}:0',
        ]),
      );
    });

    test('a pin no boundary object claims cannot be wired', () {
      final box = make(Obj.patcher);
      make(Obj.gInlet, args: '2', inside: box);
      final f = make(Obj.gSlider);
      expect(controller.graph.nodeById(box)!.inputs, hasLength(3));
      expect(controller.canConnect(outlet(f), inlet(box, 0)), isFalse);
      expect(controller.canConnect(outlet(f), inlet(box, 2)), isTrue);
    });

    test('a message is refused at a signal inlet', () {
      final g = gainBox();
      final slider = make(Obj.gSlider);
      expect(controller.canConnect(outlet(slider), inlet(g.box)), isFalse);
    });

    test('renumbering a boundary object moves its cable to the new pin', () {
      final box = make(Obj.patcher);
      final i = make(Obj.gInlet, args: '0', inside: box);
      final slider = make(Obj.gSlider);
      controller.connectViaGesture(outlet(slider), inlet(box));

      controller.applyParams(i, '3');

      expect(controller.graph.nodeById(box)!.inputs, hasLength(4));
      final cable = controller.graph.cables.single;
      expect(controller.displayPort(cable.target), inlet(box, 3));

      controller.undo();
      expect(controller.graph.nodeById(box)!.inputs, hasLength(1));
      expect(controller.displayPort(cable.target), inlet(box, 0));
    });
  });

  group('undo across nested edits', () {
    test(
      'deleting a box takes its contents and cables; undo brings all back',
      () {
        final g = gainBox();
        final src = make(Obj.dSine, args: '220');
        controller.connectViaGesture(outlet(src), inlet(g.box));
        final before = controller.graph.cables.toSet();

        controller
          ..selectNodes({g.box})
          ..deleteSelection();

        expect(controller.graph.nodes.map((n) => n.id), [src]);
        expect(controller.graph.cables, isEmpty);
        expect(gateway.instances.values.single.nodes.keys, [nativeOf(src)]);

        controller.undo();

        expect(controller.nodesIn(g.box).map((n) => n.id).toSet(), {
          g.inlet,
          g.sine,
          g.outlet,
        });
        expect(controller.graph.cables.toSet(), before);
        expect(controller.graph.nodeById(g.box)!.inputs, hasLength(1));
        // Natively back inside a box too: everything but the outer sine.
        final inst = gateway.instances.values.single;
        expect(
          inst.nodes.values.where((n) => n.container != null),
          hasLength(3),
        );

        controller.redo();
        expect(controller.graph.nodes.map((n) => n.id), [src]);
      },
    );

    test('deleting a boundary object drops the parent cable on its pin; '
        'undo puts both back', () {
      final g = gainBox();
      final src = make(Obj.dSine, args: '220');
      controller.connectViaGesture(outlet(src), inlet(g.box));

      controller
        ..selectNodes({g.inlet})
        ..deleteSelection();

      expect(controller.graph.nodeById(g.box)!.inputs, isEmpty);
      expect(
        controller.graph.cables.where((c) => c.source == outlet(src)),
        isEmpty,
      );

      controller.undo();
      expect(controller.graph.nodeById(g.box)!.inputs, hasLength(1));
      expect(
        controller.graph.cables.where((c) => c.source == outlet(src)),
        hasLength(1),
      );
    });

    test('edits inside and outside share one journal', () {
      final box = make(Obj.patcher);
      final s = make(Obj.dSine, inside: box);
      controller.undo();
      expect(controller.nodesIn(box), isEmpty);
      controller.undo();
      expect(controller.graph.nodes, isEmpty);
      controller
        ..redo()
        ..redo();
      expect(controller.containerOf(s), box);
    });
  });

  group('duplicate, copy and paste', () {
    test('duplicating a box copies its contents inside the copy', () {
      final g = gainBox();
      controller
        ..selectNodes({g.box})
        ..duplicateSelection();

      final copy = controller.graph.selectedNodes.single;
      expect(copy, isNot(g.box));
      expect(controller.containerOf(copy), isNull);
      final inside = controller.nodesIn(copy).toList();
      expect(inside.map((n) => n.type).toSet(), {
        Obj.dInlet,
        Obj.dSine,
        Obj.dOutlet,
      });
      // The contents keep their places inside; only the box moved a step.
      final original = controller.graph.nodeById(g.sine)!.position;
      expect(inside.firstWhere((n) => n.type == Obj.dSine).position, original);
      expect(controller.graph.nodeById(copy)!.inputs, hasLength(1));
      expect(
        controller.cablesWithin(inside.map((n) => n.id).toSet()),
        hasLength(2),
      );

      controller.undo();
      expect(controller.graph.nodes, hasLength(4));
    });

    test('a copied box pastes with its contents, into a subpatch too', () {
      final g = gainBox();
      final host = make(Obj.patcher, args: 'host');
      controller
        ..selectNodes({g.box})
        ..copySelection()
        ..pasteClipboard(container: host);

      final pasted = controller.graph.selectedNodes.single;
      expect(controller.containerOf(pasted), host);
      expect(controller.nodesIn(pasted), hasLength(3));
      expect(controller.scopeTitle(pasted), 'host › gain');

      controller.undo();
      expect(controller.nodesIn(host), isEmpty);
    });
  });

  group('retype', () {
    test('a box with contents keeps its type', () {
      final g = gainBox();
      expect(controller.canRetype(g.box, Obj.dSine), isFalse);
      expect(
        controller.applyBoxEdit(g.box, desc: desc(Obj.dSine), args: '1'),
        0,
      );
      expect(controller.graph.nodeById(g.box)!.type, Obj.patcher);
      expect(controller.canRetype(make(Obj.patcher), Obj.dSine), isTrue);
    });

    test('a retyped boundary object stays inside its box', () {
      final box = make(Obj.patcher);
      final i = make(Obj.gInlet, args: '0', inside: box);
      final slider = make(Obj.gSlider);
      controller.connectViaGesture(outlet(slider), inlet(box));

      final dropped = controller.applyBoxEdit(
        i,
        desc: desc(Obj.dInlet),
        args: '0',
      );

      expect(dropped, 1, reason: 'a message cannot feed a signal inlet');
      expect(controller.containerOf(i), box);
      expect(
        controller.graph.nodeById(box)!.inputs.single.kind,
        PatchPortKind.audio,
      );
      controller.undo();
      expect(controller.graph.cables, hasLength(1));
      expect(
        controller.graph.nodeById(box)!.inputs.single.kind,
        PatchPortKind.control,
      );
    });
  });

  group('selection follows the window', () {
    test('focusing another scope drops a selection made elsewhere', () {
      final g = gainBox();
      controller.selectNodes({g.sine});
      controller.focusScope(g.box);
      expect(controller.graph.selectedNodes, {g.sine});
      controller.focusScope(null);
      expect(controller.graph.selectedNodes, isEmpty);
    });

    test('a shift-click in another window starts a fresh selection', () {
      final g = gainBox();
      controller.selectNode(g.sine);
      controller.selectNode(g.box, additive: true);
      expect(controller.graph.selectedNodes, {g.box});
    });
  });

  group('rebuild from the instance', () {
    test('containment and cables through the box survive a dump → parse', () {
      final g = gainBox();
      final src = make(Obj.dSine, args: '220');
      controller.connectViaGesture(outlet(src), inlet(g.box));
      final dump = gateway.dumpJson(controller.instanceId);

      final other = gateway.createInstance();
      gateway.parseJson(other, dump);
      final reloaded = PatcherController.bound(gateway, instanceId: other)
        ..rebuildFromInstance();
      addTearDown(reloaded.dispose);

      final box = reloaded.graph.nodes.singleWhere(
        (n) => n.type == Obj.patcher,
      );
      expect(reloaded.subpatchNameOf(box.id), 'gain');
      expect(reloaded.nodesIn(box.id), hasLength(3));
      expect(box.inputs, hasLength(1));
      expect(box.outputs, hasLength(1));
      final PatchCable into = reloaded.graph.cables.singleWhere(
        (c) => reloaded.containerOf(c.source.nodeId) == null,
      );
      expect(reloaded.displayPort(into.target), inlet(box.id));
    });
  });
}
