import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:yse/yse.dart';

import '../test_doubles/fake_patcher_gateway.dart';

/// Encapsulate and de-encapsulate (issue #552): a selection moves into a new
/// `patcher` box, the cables its edge cut routed through new pins, and back.
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

  String typeOf(PatchNodeId id) => controller.graph.nodeById(id)!.type;
  Offset positionOf(PatchNodeId id) => controller.graph.nodeById(id)!.position;

  /// The cables as (source, target) pairs, as the engine records them.
  Set<(PatchPortId, PatchPortId)> wiring() => {
    for (final c in controller.graph.cables) (c.source, c.target),
  };

  /// Every native cable joins two live handles, and there are as many of them
  /// as the mirror holds — the engine and the editor agree.
  void expectNativeInSync() {
    final inst = gateway.instances.values.single;
    expect(inst.cables, hasLength(controller.graph.cables.length));
    for (final c in inst.cables) {
      expect(inst.nodes.keys, containsAll([c.fromHandleId, c.toHandleId]));
    }
    expect(inst.nodes, hasLength(controller.graph.nodes.length));
  }

  setUp(() {
    gateway = FakePatcherGateway();
    controller = PatcherController(gateway);
  });

  tearDown(() => controller.dispose());

  /// `.slider` → two `~sine`s (selected) → `~dac` (both channels from the
  /// first sine), plus a cable between the two sines.
  ({PatchNodeId slider, PatchNodeId a, PatchNodeId b, PatchNodeId dac})
  chain() {
    final slider = make(Obj.gSlider, at: const Offset(0, 0));
    final a = make(Obj.dSine, args: '440', at: const Offset(96, 160));
    final b = make(Obj.dSine, args: '220', at: const Offset(224, 128));
    final dac = make(Obj.dDac, at: const Offset(96, 400));
    controller
      ..connect(outlet(slider), inlet(a))
      ..connect(outlet(slider), inlet(b))
      ..connect(outlet(a), inlet(b))
      ..connect(outlet(a), inlet(dac, 0))
      ..connect(outlet(a), inlet(dac, 1));
    return (slider: slider, a: a, b: b, dac: dac);
  }

  group('encapsulate', () {
    test('moves the selection into a box at its place, one pin per source', () {
      final c = chain();
      controller.selectNodes({c.a, c.b});

      final box = controller.encapsulateSelection()!;

      expect(typeOf(box), Obj.patcher);
      expect(controller.containerOf(box), isNull);
      expect(positionOf(box), const Offset(96, 128));
      expect(controller.graph.selectedNodes, {box});
      expect(controller.containerOf(c.a), box);
      expect(controller.containerOf(c.b), box);
      expect(controller.nodesIn(null).map((n) => n.id).toSet(), {
        c.slider,
        box,
        c.dac,
      });

      final pins = controller
          .nodesIn(box)
          .where((n) => n.id != c.a && n.id != c.b);
      final inletPin = pins.singleWhere((n) => n.type == Obj.gInlet).id;
      final outletPin = pins.singleWhere((n) => n.type == Obj.dOutlet).id;
      expect(controller.argsOf(inletPin), '0');
      expect(controller.argsOf(outletPin), '0');

      final node = controller.graph.nodeById(box)!;
      expect(node.inputs.map((p) => p.kind), [PatchPortKind.control]);
      expect(node.outputs.map((p) => p.kind), [PatchPortKind.audio]);

      expect(wiring(), {
        (outlet(c.slider), inlet(inletPin)),
        (outlet(inletPin), inlet(c.a)),
        (outlet(inletPin), inlet(c.b)),
        (outlet(c.a), inlet(c.b)),
        (outlet(c.a), inlet(outletPin)),
        (outlet(outletPin), inlet(c.dac, 0)),
        (outlet(outletPin), inlet(c.dac, 1)),
      });
      // The parent sees the cables on the box.
      final into = controller.graph.cables.firstWhere(
        (k) => k.source == outlet(c.slider),
      );
      expect(controller.displayPort(into.target), inlet(box));
      final out = controller.graph.cables.firstWhere(
        (k) => k.target == inlet(c.dac, 1),
      );
      expect(controller.displayPort(out.source), outlet(box));
      expectNativeInSync();
    });

    test('lays the contents out from the top left, pins above and below', () {
      final c = chain();
      controller.selectNodes({c.a, c.b});
      final box = controller.encapsulateSelection()!;

      final pins = controller
          .nodesIn(box)
          .where((n) => n.id != c.a && n.id != c.b);
      final inletPin = pins.singleWhere((n) => n.type == Obj.gInlet);
      final outletPin = pins.singleWhere((n) => n.type == Obj.dOutlet);
      // The selection's top left (96, 128) lands at (32, 80): a margin, and
      // room for the inlet row.
      expect(positionOf(c.a), const Offset(32, 112));
      expect(positionOf(c.b), const Offset(160, 80));
      expect(inletPin.position.dy, 32);
      expect(inletPin.position.dx, 32, reason: 'above the first target');
      final bottom =
          controller.graph.nodeById(c.a)!.position.dy +
          controller.graph.nodeById(c.a)!.size.height;
      expect(outletPin.position.dy, greaterThan(bottom));
    });

    test('numbers pins left to right by where their outside end sits', () {
      final right = make(Obj.gSlider, at: const Offset(600, 0));
      final left = make(Obj.gSlider, at: const Offset(0, 0));
      final dacRight = make(Obj.dDac, at: const Offset(600, 400));
      final dacLeft = make(Obj.dDac, at: const Offset(0, 400));
      final a = make(Obj.dSine, at: const Offset(200, 200));
      final b = make(Obj.dSine, at: const Offset(300, 200));
      controller
        ..connect(outlet(right), inlet(a))
        ..connect(outlet(left), inlet(b))
        ..connect(outlet(a), inlet(dacLeft))
        ..connect(outlet(b), inlet(dacRight))
        ..selectNodes({a, b});

      final box = controller.encapsulateSelection()!;

      PatchNodeId pinFeeding(PatchPortId target) => controller.graph.cables
          .firstWhere((k) => k.target == target)
          .source
          .nodeId;
      expect(controller.argsOf(pinFeeding(inlet(b))), '0', reason: 'left');
      expect(controller.argsOf(pinFeeding(inlet(a))), '1', reason: 'right');
      expect(controller.argsOf(pinFeeding(inlet(dacLeft))), '0');
      expect(controller.argsOf(pinFeeding(inlet(dacRight))), '1');
      expect(controller.graph.nodeById(box)!.inputs, hasLength(2));
      expect(controller.graph.nodeById(box)!.outputs, hasLength(2));
    });

    test(
      'is one undo step; redo brings the box and pins back as they were',
      () {
        final c = chain();
        final before = wiring();
        final positions = {
          for (final n in controller.graph.nodes) n.id: n.position,
        };
        controller.selectNodes({c.a, c.b});
        final box = controller.encapsulateSelection()!;
        final inside = controller.nodesIn(box).map((n) => n.id).toSet();
        final after = wiring();

        controller.undo();

        expect(controller.graph.nodeById(box), isNull);
        expect(wiring(), before);
        for (final MapEntry(key: id, value: at) in positions.entries) {
          expect(positionOf(id), at);
          expect(controller.containerOf(id), isNull);
        }
        expect(controller.graph.selectedNodes, {c.a, c.b});
        expectNativeInSync();

        controller.redo();

        expect(controller.containerOf(c.a), box);
        expect(controller.nodesIn(box).map((n) => n.id).toSet(), inside);
        expect(wiring(), after);
        expect(controller.graph.selectedNodes, {box});
        expectNativeInSync();

        controller.undo();
        expect(wiring(), before);
        expectNativeInSync();
      },
    );

    test('works inside a subpatch window, through its own pins', () {
      final outer = make(Obj.patcher, args: 'fx');
      final pin = make(Obj.dInlet, args: '0', inside: outer);
      final sine = make(Obj.dSine, inside: outer, at: const Offset(64, 96));
      final src = make(Obj.dSine);
      controller
        ..connect(outlet(src), inlet(outer))
        ..connect(outlet(pin), inlet(sine))
        ..selectNodes({sine});

      final box = controller.encapsulateSelection()!;

      expect(controller.containerOf(box), outer);
      expect(controller.containerOf(sine), box);
      final inner = controller.nodesIn(box).singleWhere((n) => n.id != sine);
      expect(inner.type, Obj.dInlet, reason: 'an audio cable');
      expect(wiring(), {
        (outlet(src), inlet(pin)),
        (outlet(pin), inlet(inner.id)),
        (outlet(inner.id), inlet(sine)),
      });
      expect(controller.displayPort(inlet(inner.id)), inlet(box));
      expectNativeInSync();
    });

    test('a selected box keeps its contents; its pins are routed through', () {
      final gain = make(Obj.patcher, args: 'gain', at: const Offset(100, 100));
      final gi = make(Obj.dInlet, args: '0', inside: gain);
      final go = make(Obj.dOutlet, args: '0', inside: gain);
      controller.connect(outlet(gi), inlet(go));
      final src = make(Obj.dSine);
      final dac = make(Obj.dDac, at: const Offset(100, 300));
      controller
        ..connect(outlet(src), inlet(gain))
        ..connect(outlet(gain), inlet(dac))
        ..selectNodes({gain});

      final box = controller.encapsulateSelection()!;

      expect(controller.containerOf(gain), box);
      expect(controller.nodesIn(gain).map((n) => n.id).toSet(), {gi, go});
      final pins = controller.nodesIn(box).where((n) => n.id != gain).toList();
      final i = pins.singleWhere((n) => n.type == Obj.dInlet).id;
      final o = pins.singleWhere((n) => n.type == Obj.dOutlet).id;
      expect(wiring(), {
        (outlet(src), inlet(i)),
        (outlet(i), inlet(gi)),
        (outlet(gi), inlet(go)),
        (outlet(go), inlet(o)),
        (outlet(o), inlet(dac)),
      });
      expect(controller.displayPort(inlet(gi)), inlet(gain));
      expectNativeInSync();
    });

    test('refuses a selection holding an inlet or outlet object', () {
      final box = make(Obj.patcher);
      final pin = make(Obj.gInlet, args: '0', inside: box);
      final s = make(Obj.dSine, inside: box);
      controller.selectNodes({pin, s});

      expect(controller.canEncapsulate, isFalse);
      expect(controller.encapsulateSelection(), isNull);
      expect(controller.containerOf(s), box);

      controller.selectNodes({});
      expect(controller.canEncapsulate, isFalse);
    });
  });

  group('de-encapsulate', () {
    test('undoes an encapsulate by hand: same objects, wiring and places', () {
      final c = chain();
      final before = wiring();
      final positions = {
        for (final n in controller.graph.nodes) n.id: n.position,
      };
      controller.selectNodes({c.a, c.b});
      final box = controller.encapsulateSelection()!;

      controller.deencapsulateSelection();

      expect(controller.graph.nodeById(box), isNull);
      expect(controller.graph.nodes.map((n) => n.id).toSet(), positions.keys);
      expect(wiring(), before);
      for (final MapEntry(key: id, value: at) in positions.entries) {
        expect(positionOf(id), at, reason: '$id');
        expect(controller.containerOf(id), isNull);
      }
      expect(controller.graph.selectedNodes, {c.a, c.b});
      expectNativeInSync();
    });

    test('wires straight through a pin wired straight to another pin', () {
      final gain = make(Obj.patcher, at: const Offset(100, 100));
      final gi = make(Obj.dInlet, args: '0', inside: gain);
      final go = make(Obj.dOutlet, args: '0', inside: gain);
      final inner = make(Obj.dSine, inside: gain, at: const Offset(40, 40));
      controller.connect(outlet(gi), inlet(go));
      final src = make(Obj.dSine);
      final dac = make(Obj.dDac, at: const Offset(100, 300));
      controller
        ..connect(outlet(src), inlet(gain))
        ..connect(outlet(gain), inlet(dac, 1))
        ..selectNodes({gain});

      controller.deencapsulateSelection();

      expect(controller.graph.nodes.map((n) => n.id).toSet(), {
        src,
        dac,
        inner,
      });
      expect(positionOf(inner), const Offset(100, 100));
      expect(wiring(), {(outlet(src), inlet(dac, 1))});
      expectNativeInSync();
    });

    test('is one undo step that brings the box back under its own ids', () {
      final gain = make(Obj.patcher, args: 'gain', at: const Offset(100, 100));
      final gi = make(Obj.dInlet, args: '0', inside: gain);
      final s = make(Obj.dSine, inside: gain, at: const Offset(40, 80));
      final go = make(Obj.dOutlet, args: '0', inside: gain);
      final src = make(Obj.dSine);
      final dac = make(Obj.dDac, at: const Offset(100, 300));
      controller
        ..connect(outlet(gi), inlet(s))
        ..connect(outlet(s), inlet(go))
        ..connect(outlet(src), inlet(gain))
        ..connect(outlet(gain), inlet(dac));
      final before = wiring();
      controller.selectNodes({gain});

      controller.deencapsulateSelection();
      final after = wiring();
      expect(after, {(outlet(src), inlet(s)), (outlet(s), inlet(dac))});
      expect(controller.containerOf(s), isNull);

      controller.undo();
      expect(controller.subpatchNameOf(gain), 'gain');
      expect(positionOf(gain), const Offset(100, 100));
      expect(controller.nodesIn(gain).map((n) => n.id).toSet(), {gi, s, go});
      expect(positionOf(s), const Offset(40, 80));
      expect(wiring(), before);
      expect(controller.graph.nodeById(gain)!.inputs, hasLength(1));
      expect(controller.graph.selectedNodes, {gain});
      expectNativeInSync();

      controller.redo();
      expect(controller.graph.nodeById(gain), isNull);
      expect(wiring(), after);
      expectNativeInSync();
    });

    test('is a no-op with no subpatch box selected', () {
      final s = make(Obj.dSine);
      controller
        ..selectNodes({s})
        ..deencapsulateSelection();
      expect(controller.undoScope.canUndo, isTrue, reason: 'the create only');
      controller.undo();
      expect(controller.undoScope.canUndo, isFalse);
    });
  });
}
