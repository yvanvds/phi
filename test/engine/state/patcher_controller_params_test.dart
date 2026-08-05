import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_canvas_constants.dart';
import 'package:phi/domain/patcher/patch_args.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/engine/bridge/patcher_node_snapshot.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:yse/yse.dart';

import '../test_doubles/fake_patcher_gateway.dart';

/// Unit tests for the controller surface the live GUI bodies and params dialog
/// depend on (issue #223): `guiValueOf`, `setControlValue`/`setControlBang`,
/// and the undoable `applyParams` / `setParams` path — plus the post-apply port
/// re-inspect that keeps the mirror honest when arguments change an object's
/// arity (issue #356).
void main() {
  late FakePatcherGateway gateway;
  late PatcherController controller;

  NodeDescriptor desc(String type, {String args = ''}) => NodeDescriptor(
    type: type,
    title: type,
    defaultSize: const Size(120, 80),
    defaultArgs: args,
    inputs: const [],
    outputs: const [],
    buildBody: (ctx, node, controller) => const SizedBox.shrink(),
  );

  setUp(() {
    gateway = FakePatcherGateway();
    controller = PatcherController(gateway);
  });

  tearDown(() => controller.dispose());

  test('guiValueOf reads the gateway value; a sendFloat refreshes it', () {
    final node = controller.addNode(
      desc: desc(Obj.gFloat),
      position: Offset.zero,
    );
    expect(controller.guiValueOf(node.id), '');

    controller.setControlValue(node.id, inlet: 0, value: 0.5);
    expect(controller.guiValueOf(node.id), '0.5');
  });

  test('setControlBang reaches the gateway', () {
    final node = controller.addNode(
      desc: desc(Obj.gButton),
      position: Offset.zero,
    );
    controller.setControlBang(node.id, inlet: 0);
    final handle = gateway.nodes.keys.single;
    expect(gateway.calls, contains('sendBang:$handle:0'));
  });

  test('applyParams is undoable and persists through setParams', () {
    final sineDesc = gateway.objectTypes().firstWhere(
      (d) => d.type == Obj.dSine,
    );
    final node = controller.addObject(desc: sineDesc, position: Offset.zero);
    expect(controller.argsOf(node.id), '440'); // documented default

    controller.applyParams(node.id, '880');
    final handle = gateway.nodes.keys.single;
    expect(controller.argsOf(node.id), '880');
    expect(gateway.calls, contains('setParams:$handle:880'));

    controller.undo();
    expect(controller.argsOf(node.id), '440');

    controller.redo();
    expect(controller.argsOf(node.id), '880');
  });

  test('setNodeParams wakes the node so a body rendering its args repaints', () {
    // Issue #354: the `~sine` readout is rebuilt by the node's own listener, so
    // apply *and* undo/redo have to raise it — otherwise the canvas keeps
    // showing the previous frequency.
    final node = controller.addObject(
      desc: gateway.objectTypes().firstWhere((d) => d.type == Obj.dSine),
      position: Offset.zero,
    );
    var notified = 0;
    node.addListener(() => notified++);

    controller.applyParams(node.id, '880');
    expect(notified, 1);

    controller.undo();
    expect(notified, 2);

    controller.redo();
    expect(notified, 3);
  });

  test('applyParams with unchanged args records nothing', () {
    final node = controller.addObject(
      desc: gateway.objectTypes().firstWhere((d) => d.type == Obj.dSine),
      position: Offset.zero,
    );
    controller.applyParams(node.id, controller.argsOf(node.id));
    expect(controller.undoScope.canUndo, isFalse);
  });

  // ─── port topology follows the arguments (issue #356) ──────────────────
  //
  // An object's inlet/outlet count is decided by its creation arguments, so a
  // `setParams` can reshape the very object the canvas is drawing. Before this
  // the mirror kept the old ports: dots drawn where the object has none, and
  // cables still wired to outlets the engine had forgotten.

  group('port topology after a params change', () {
    /// A type whose **outlet count is one per creation argument** — the arity
    /// pattern `.select`-style objects have. Modelled on the gateway, so the
    /// controller learns about the reshape the only way it can in production:
    /// by re-inspecting the native object.
    const fanType = '.fan';

    setUp(() {
      gateway.topologyResolver = (type, args) {
        if (type != fanType) return null;
        final outlets = splitPatchArgs(args).length;
        return PatcherNodeSnapshot(
          inputs: 1,
          outputs: outlets,
          inputKinds: const [PatchPortKind.control],
          outputKinds: [
            for (var i = 0; i < outlets; i++) PatchPortKind.control,
          ],
        );
      };
    });

    PatchNode addFan(String args) => controller.addNode(
      desc: desc(fanType, args: args),
      position: Offset.zero,
    );

    PatchPortId out(PatchNode n, int i) =>
        PatchPortId(nodeId: n.id, side: PatchPortSide.output, index: i);
    PatchPortId inp(PatchNode n, int i) =>
        PatchPortId(nodeId: n.id, side: PatchPortSide.input, index: i);

    test('arguments that add outlets grow the node — wider, not taller', () {
      final fan = addFan('1 2');
      expect(fan.outputs, hasLength(2));
      expect(fan.size, const Size(120, 80));

      controller.applyParams(fan.id, '1 2 3 4 5 6');

      expect(fan.outputs, hasLength(6));
      expect(fan.outputs.last.index, 5);
      // Ports spread along the horizontal edges since #377, so the box grows
      // *wider* to seat the extra ones rather than drawing them past its own
      // right edge — and its height, which no longer answers to the port
      // count, is left exactly as the descriptor tuned it.
      expect(fan.size.width, PatchCanvasConstants.minWidthForPorts(6));
      expect(fan.size.width, greaterThan(120));
      expect(fan.size.height, 80);
    });

    test('losing an outlet drops the cables that hung off it, and undo wires '
        'them back', () {
      final fan = addFan('1 2 3');
      final sink = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(300, 0),
      );
      // Two cables: one off the outlet that survives, one off the one that goes.
      expect(controller.connect(out(fan, 0), inp(sink, 0)), isTrue);
      expect(controller.connect(out(fan, 2), inp(sink, 0)), isTrue);
      expect(gateway.cables, hasLength(2));

      controller.applyParams(fan.id, '1 2');

      expect(fan.outputs, hasLength(2));
      // Only the stranded cable went — and it went from the native patcher too,
      // not just the mirror.
      expect(controller.graph.cables, hasLength(1));
      expect(controller.graph.cables.single.source, out(fan, 0));
      expect(gateway.cables, hasLength(1));

      controller.undo();

      expect(fan.outputs, hasLength(3));
      expect(controller.graph.cables, hasLength(2));
      expect(gateway.cables, hasLength(2));

      controller.redo();

      expect(fan.outputs, hasLength(2));
      expect(controller.graph.cables, hasLength(1));
    });

    test('an unchanged topology leaves the ports and cables alone', () {
      final fan = addFan('1 2');
      final sink = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(300, 0),
      );
      controller.connect(out(fan, 1), inp(sink, 0));
      final ports = fan.outputs;

      // Same argument *count*, different values: the object keeps its shape.
      controller.applyParams(fan.id, '7 9');

      expect(fan.outputs, same(ports));
      expect(controller.graph.cables, hasLength(1));
    });
  });

  test('the read/write helpers tolerate an unknown handle', () {
    // No object was created under this id — the helpers must not throw.
    const unknown = PatchNodeId(999);
    expect(controller.guiValueOf(unknown), '');
    expect(
      () => controller.setControlValue(unknown, inlet: 0, value: 1),
      returnsNormally,
    );
    expect(() => controller.setControlBang(unknown, inlet: 0), returnsNormally);
    expect(controller.setNodeParams(unknown, '1 2'), isEmpty);
  });
}
