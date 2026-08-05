import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/bridge/patcher_node_snapshot.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:yse/yse.dart';

import '../test_doubles/fake_patcher_gateway.dart';

/// Retyping an object in place (issue #383): the object under the box becomes a
/// *different* object, and everything the patch knows it by has to survive that
/// — its logical id, its position, its selection, and every cable the new type
/// still has room for.
///
/// The engine has no verb for it: the native object is deleted and another one
/// minted, which is precisely why these tests watch the gateway calls as well as
/// the mirror. And because a retype can cost the patch a connection, the undo of
/// one has to give the connection back — the assertion the whole slice turns on.
void main() {
  late FakePatcherGateway gateway;
  late PatcherController controller;

  /// A second oscillator to retype *into*: same shape as `~sine`, so a `sine`
  /// becoming a `saw` keeps both its cables.
  const saw = PatchObjectDescriptor(
    type: '~saw',
    description: 'sawtooth oscillator',
    category: PatchObjectCategory.oscillator,
    isDsp: true,
    inlets: [
      PatchInletDescriptor(
        label: 'freq',
        doc: 'frequency in Hz',
        range: '0..20000',
        accepts: {PatchInletAccept.buffer, PatchInletAccept.float},
      ),
    ],
    outlets: [
      PatchOutletDescriptor(
        label: 'out',
        doc: 'signal',
        range: '',
        type: PatchOutletType.buffer,
      ),
    ],
    params: [
      PatchParamDescriptor(
        name: 'frequency',
        doc: 'initial frequency',
        defaultValue: '440',
        range: '0..20000',
      ),
    ],
  );

  /// A **control-rate** object of the same arity — one inlet taking a float, one
  /// float outlet. Retyping into it keeps the cables (a `~sine` inlet accepts a
  /// float too) but changes what runs down them, so it is what proves a carried
  /// cable is rebuilt rather than re-filed.
  const counter = PatchObjectDescriptor(
    type: '.count',
    description: 'counter',
    category: PatchObjectCategory.math,
    isDsp: false,
    inlets: [
      PatchInletDescriptor(
        label: 'in',
        doc: 'step',
        range: '',
        accepts: {PatchInletAccept.float, PatchInletAccept.bang},
      ),
    ],
    outlets: [
      PatchOutletDescriptor(
        label: 'out',
        doc: 'count',
        range: '',
        type: PatchOutletType.float,
      ),
    ],
    params: [],
  );

  PatchObjectDescriptor typed(String type) =>
      gateway.objectTypes().firstWhere((d) => d.type == type);

  PatchPortId out(PatchNodeId id, int i) =>
      PatchPortId(nodeId: id, side: PatchPortSide.output, index: i);
  PatchPortId inp(PatchNodeId id, int i) =>
      PatchPortId(nodeId: id, side: PatchPortSide.input, index: i);

  PatchNode nodeAt(PatchNodeId id) => controller.graph.nodeById(id)!;

  setUp(() {
    NodeTypeRegistry.instance.clear();
    gateway = FakePatcherGateway()
      ..objectTypesCatalogue = [
        ...FakePatcherGateway.defaultCatalogue,
        saw,
        counter,
      ];
    gateway.topologyOverrides['~saw'] = const PatcherNodeSnapshot(
      inputs: 1,
      outputs: 1,
      inputKinds: [PatchPortKind.control],
      outputKinds: [PatchPortKind.audio],
    );
    gateway.topologyOverrides['.count'] = const PatcherNodeSnapshot(
      inputs: 1,
      outputs: 1,
      inputKinds: [PatchPortKind.control],
      outputKinds: [PatchPortKind.control],
    );
    controller = PatcherController(gateway);
  });

  tearDown(() {
    controller.dispose();
    NodeTypeRegistry.instance.clear();
  });

  /// `slider → sine → dac`, the patch every case below retypes the middle of.
  ({PatchNodeId slider, PatchNodeId sine, PatchNodeId dac}) seed() {
    final slider = controller.addObject(
      desc: typed(Obj.gSlider),
      position: const Offset(40, 40),
    );
    final sine = controller.addObject(
      desc: typed(Obj.dSine),
      position: const Offset(200, 160),
    );
    final dac = controller.addObject(
      desc: typed(Obj.dDac),
      position: const Offset(360, 300),
    );
    expect(controller.connect(out(slider.id, 0), inp(sine.id, 0)), isTrue);
    expect(controller.connect(out(sine.id, 0), inp(dac.id, 0)), isTrue);
    return (slider: slider.id, sine: sine.id, dac: dac.id);
  }

  test(
    'a retype replaces the object and keeps its id, position and selection',
    () {
      final ids = seed();
      controller.selectNode(ids.sine);
      final before = gateway.nodes.length;

      final dropped = controller.applyBoxEdit(ids.sine, desc: saw, args: '300');

      expect(dropped, 0);
      final node = nodeAt(ids.sine);
      expect(node.type, '~saw');
      expect(controller.argsOf(ids.sine), '300');
      expect(controller.objectLineOf(ids.sine), 'saw 300');
      // Same logical node: the position it was dragged to, and the ring it was
      // carrying, are both still there.
      expect(node.position, const Offset(200, 160));
      expect(controller.graph.selectedNodes, {ids.sine});
      // The native object really was swapped — deleted and re-minted, not
      // reconfigured — and the count is unchanged, so nothing leaked.
      expect(gateway.nodes.length, before);
      expect(
        gateway.calls.where((c) => c.startsWith('createObject')).last,
        contains(':~saw:300'),
      );
      expect(gateway.calls, contains('deleteObject:2'));
      // Placed where the old object stood, so a reload finds it there.
      expect(gateway.nodes.values.last.position, const Offset(200, 160));
    },
  );

  test('cables whose endpoints still exist are carried across', () {
    final ids = seed();

    controller.applyBoxEdit(ids.sine, desc: saw, args: '300');

    // Both cables still land: the slider still reaches the new oscillator's
    // inlet, and its outlet still reaches the dac.
    expect(controller.graph.cables, hasLength(2));
    expect(
      controller.graph.cables.map((c) => (c.source, c.target)),
      containsAll([
        (out(ids.slider, 0), inp(ids.sine, 0)),
        (out(ids.sine, 0), inp(ids.dac, 0)),
      ]),
    );
    // …and in the native patcher too, not just the mirror.
    expect(gateway.cables, hasLength(2));
  });

  test('a carried cable takes the new object\'s outlet kind', () {
    final ids = seed();
    expect(
      controller.graph.cables
          .firstWhere((c) => c.source == out(ids.sine, 0))
          .kind,
      PatchPortKind.audio,
    );

    // A `~sine` inlet accepts a float, so the slider's cable survives the
    // retype — but what comes *out* is control-rate now, and the cable has to
    // say so or the canvas draws a signal wire carrying numbers.
    controller.applyBoxEdit(ids.sine, desc: counter, args: '');

    final carried = controller.graph.cables.singleWhere(
      (c) => c.source == out(ids.sine, 0) || c.target == inp(ids.sine, 0),
    );
    expect(carried.target, inp(ids.sine, 0));
    expect(nodeAt(ids.sine).outputs.single.kind, PatchPortKind.control);
    // The outgoing one went instead: a float outlet cannot feed the dac.
    expect(controller.graph.cables, hasLength(1));
  });

  test('cables the new type has no room for are dropped and counted', () {
    final ids = seed();

    // A `.slider` has **no inlet at all** and emits a float: the cable arriving
    // from the slider has nowhere to land, and the one leaving for the dac is
    // no longer a signal the dac accepts.
    final dropped = controller.applyBoxEdit(
      ids.sine,
      desc: typed(Obj.gSlider),
      args: '',
    );

    expect(dropped, 2);
    expect(controller.graph.cables, isEmpty);
    expect(gateway.cables, isEmpty);
    expect(nodeAt(ids.sine).type, Obj.gSlider);
  });

  test('one undo puts the object, its arguments and every dropped cable back', () {
    final ids = seed();
    final dropped = controller.applyBoxEdit(
      ids.sine,
      desc: typed(Obj.gSlider),
      args: '',
    );
    expect(dropped, 2);

    controller.undo();

    // The whole retype was one step: the old object is back under the same id,
    // carrying the arguments it had — and so are both cables, which is the part
    // a delete-then-create could never give back.
    final node = nodeAt(ids.sine);
    expect(node.type, Obj.dSine);
    expect(controller.argsOf(ids.sine), '440');
    expect(node.position, const Offset(200, 160));
    expect(controller.graph.cables, hasLength(2));
    expect(gateway.cables, hasLength(2));

    controller.redo();

    expect(nodeAt(ids.sine).type, Obj.gSlider);
    expect(controller.graph.cables, isEmpty);
  });

  test('an unchanged type is an argument edit, not a retype', () {
    final ids = seed();
    final before = gateway.nodes.keys.toList();

    final dropped = controller.applyBoxEdit(
      ids.sine,
      desc: typed(Obj.dSine),
      args: '220',
    );

    expect(dropped, 0);
    expect(controller.argsOf(ids.sine), '220');
    // Reconfigured through `setParams` — the native object is the one that was
    // already there, and the cables never came off it.
    expect(gateway.nodes.keys, before);
    expect(gateway.calls.any((c) => c.startsWith('setParams')), isTrue);
    expect(controller.graph.cables, hasLength(2));

    controller.undo();
    expect(controller.argsOf(ids.sine), '440');
  });

  test('an unchanged line records nothing at all', () {
    final ids = seed();

    controller.applyBoxEdit(ids.sine, desc: typed(Obj.dSine), args: '440');

    expect(controller.undoScope.canUndo, isFalse);
  });

  test('the retype path tolerates an unknown node', () {
    const unknown = PatchNodeId(999);
    expect(controller.applyBoxEdit(unknown, desc: saw, args: '300'), 0);
    expect(
      controller.retypeNodePrimitive(unknown, type: '~saw', args: '300'),
      isEmpty,
    );
    expect(controller.undoScope.canUndo, isFalse);
  });
}
