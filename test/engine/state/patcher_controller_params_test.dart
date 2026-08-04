import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:yse/yse.dart';

import '../test_doubles/fake_patcher_gateway.dart';

/// Unit tests for the controller surface the live GUI bodies and params dialog
/// depend on (issue #223): `guiValueOf`, `setControlValue`/`setControlBang`,
/// and the undoable `applyParams` / `setParams` path.
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

  test('the read/write helpers tolerate an unknown handle', () {
    // No object was created under this id — the helpers must not throw.
    const unknown = PatchNodeId(999);
    expect(controller.guiValueOf(unknown), '');
    expect(
      () => controller.setControlValue(unknown, inlet: 0, value: 1),
      returnsNormally,
    );
    expect(() => controller.setControlBang(unknown, inlet: 0), returnsNormally);
    expect(() => controller.setNodeParams(unknown, '1 2'), returnsNormally);
  });
}
