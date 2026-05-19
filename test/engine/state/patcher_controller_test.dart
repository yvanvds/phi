import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:yse/yse.dart';

import '../test_doubles/fake_patcher_gateway.dart';

NodeDescriptor _descSine() => NodeDescriptor(
  type: Obj.dSine,
  title: 'osc · sine',
  defaultSize: const Size(130, 70),
  defaultArgs: '440',
  inputs: const [PortSpec(kind: PatchPortKind.control)],
  outputs: const [PortSpec(kind: PatchPortKind.audio)],
  buildBody: (ctx, node, controller) => const SizedBox.shrink(),
);

NodeDescriptor _descSlider() => NodeDescriptor(
  type: Obj.gSlider,
  title: 'slider',
  defaultSize: const Size(80, 170),
  defaultArgs: '0 1 0.5',
  inputs: const [],
  outputs: const [PortSpec(kind: PatchPortKind.control)],
  buildBody: (ctx, node, controller) => const SizedBox.shrink(),
);

NodeDescriptor _descDac() => NodeDescriptor(
  type: Obj.dDac,
  title: 'out',
  defaultSize: const Size(110, 60),
  defaultArgs: '',
  inputs: const [PortSpec(kind: PatchPortKind.audio)],
  outputs: const [],
  buildBody: (ctx, node, controller) => const SizedBox.shrink(),
);

void main() {
  group('PatcherController (FakePatcherGateway)', () {
    late FakePatcherGateway gateway;
    late PatcherController controller;

    setUp(() {
      gateway = FakePatcherGateway()..init();
      controller = PatcherController(gateway);
    });

    tearDown(() => controller.dispose());

    test('addNode forwards to gateway and reifies port topology', () {
      final n = controller.addNode(
        desc: _descSine(),
        position: const Offset(40, 60),
      );

      expect(gateway.calls.first, startsWith('init'));
      expect(
        gateway.calls,
        containsAllInOrder(<String>[
          'createObject:1:~sine:440',
          'setNodePosition:1:40.0:60.0',
        ]),
      );
      expect(n.inputs, hasLength(1));
      expect(n.outputs, hasLength(1));
      expect(n.outputs.single.kind, PatchPortKind.audio);
    });

    test('moveNode applies delta and persists to gateway', () {
      final n = controller.addNode(
        desc: _descSine(),
        position: const Offset(40, 60),
      );

      controller.moveNode(n.id, const Offset(10, 5));

      expect(n.position, const Offset(50, 65));
      expect(gateway.calls.last, 'setNodePosition:${n.id.value}:50.0:65.0');
    });

    test('connect is permissive across kinds — YSE inlets are polymorphic', () {
      // `~sine`'s inlet[0] accepts both buffer (audio) and float (control)
      // in C++, so the controller must not enforce kind matching. The
      // native side silently ignores messages it can't consume.
      final slider = controller.addNode(
        desc: _descSlider(),
        position: Offset.zero,
      );
      final dac = controller.addNode(desc: _descDac(), position: Offset.zero);

      final ok = controller.connect(
        PatchPortId(nodeId: slider.id, side: PatchPortSide.output, index: 0),
        PatchPortId(nodeId: dac.id, side: PatchPortSide.input, index: 0),
      );

      expect(ok, isTrue);
      expect(controller.graph.cables, hasLength(1));
      expect(gateway.cables, hasLength(1));
    });

    test('connect writes the cable to the gateway with the right indices', () {
      final slider = controller.addNode(
        desc: _descSlider(),
        position: Offset.zero,
      );
      final sine = controller.addNode(desc: _descSine(), position: Offset.zero);

      final ok = controller.connect(
        PatchPortId(nodeId: slider.id, side: PatchPortSide.output, index: 0),
        PatchPortId(nodeId: sine.id, side: PatchPortSide.input, index: 0),
      );

      expect(ok, isTrue);
      expect(controller.graph.cables, hasLength(1));
      expect(gateway.cables, hasLength(1));
      expect(gateway.cables.single.fromHandleId, slider.id.value);
      expect(gateway.cables.single.toHandleId, sine.id.value);
    });

    test('removeNode deletes touching cables before the node', () {
      final slider = controller.addNode(
        desc: _descSlider(),
        position: Offset.zero,
      );
      final sine = controller.addNode(desc: _descSine(), position: Offset.zero);
      controller.connect(
        PatchPortId(nodeId: slider.id, side: PatchPortSide.output, index: 0),
        PatchPortId(nodeId: sine.id, side: PatchPortSide.input, index: 0),
      );

      controller.removeNode(sine.id);

      expect(controller.graph.cables, isEmpty);
      expect(gateway.cables, isEmpty);
      final disconnectIdx = gateway.calls.indexWhere(
        (c) => c.startsWith('disconnect'),
      );
      final deleteIdx = gateway.calls.indexWhere(
        (c) => c.startsWith('deleteObject:'),
      );
      expect(disconnectIdx, lessThan(deleteIdx));
    });

    test('setControlValue forwards as sendFloat', () {
      final slider = controller.addNode(
        desc: _descSlider(),
        position: Offset.zero,
      );

      controller.setControlValue(slider.id, inlet: 0, value: 0.42);

      expect(gateway.calls.last, 'sendFloat:${slider.id.value}:0:0.420');
    });

    test('connect rejects out-of-range port indices', () {
      final sine = controller.addNode(desc: _descSine(), position: Offset.zero);

      final ok = controller.connect(
        PatchPortId(nodeId: sine.id, side: PatchPortSide.output, index: 5),
        PatchPortId(nodeId: sine.id, side: PatchPortSide.input, index: 0),
      );

      expect(ok, isFalse);
    });
  });
}
