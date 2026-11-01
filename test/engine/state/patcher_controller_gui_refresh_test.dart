import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:yse/yse.dart';

import '../test_doubles/fake_patcher_gateway.dart';

/// Unit tests for the gated live-value refresh (issue #357).
///
/// A value arriving over a *cable* moves the native object and tells the Dart
/// side nothing, so before this the canvas simply never showed it. These cover
/// the ask side of the fix: which nodes get read, when a read counts as a
/// change, and what the surface's poller consults to decide whether to run at
/// all.
void main() {
  late FakePatcherGateway gateway;
  late PatcherController controller;

  NodeDescriptor desc(
    String type, {
    String args = '',
    bool readsGuiValue = false,
  }) => NodeDescriptor(
    type: type,
    defaultSize: const Size(120, 80),
    defaultArgs: args,
    inputs: const [],
    outputs: const [],
    buildBody: (ctx, node, controller) => const SizedBox.shrink(),
    readsGuiValue: readsGuiValue,
  );

  /// Register [type] as a body that displays a `guiValue`, then create one.
  PatchNode addPollable(String type) {
    NodeTypeRegistry.instance.register(desc(type, readsGuiValue: true));
    return controller.addNode(
      desc: desc(type, readsGuiValue: true),
      position: Offset.zero,
    );
  }

  /// Model a value arriving from outside Dart — a cable firing into [node]'s
  /// inlet, a script, another editor. The gateway's object is written directly,
  /// exactly as the native side would be, with nothing told to the Dart mirror.
  /// A logical node id mirrors its native handle, which is the gateway's key.
  void driveFromEngine(PatchNode node, String value) =>
      gateway.nodes[node.id.value]!.guiValue = value;

  setUp(() {
    gateway = FakePatcherGateway();
    controller = PatcherController(gateway);
    NodeTypeRegistry.instance.clear();
  });

  tearDown(() {
    controller.dispose();
    NodeTypeRegistry.instance.clear();
  });

  test('a cable-driven value wakes the node it landed on', () {
    final node = addPollable(Obj.gFloat);
    var notified = 0;
    node.addListener(() => notified++);

    driveFromEngine(node, '7');

    expect(controller.refreshGuiValues(), 1);
    expect(notified, 1);
    expect(node.guiRevision, 1);
    expect(controller.guiValueOf(node.id), '7');
  });

  test('an unchanged value wakes nothing, however often it is polled', () {
    final node = addPollable(Obj.gFloat);
    var notified = 0;
    node.addListener(() => notified++);

    // The idle case the gate exists for: a patch nobody is driving must cost no
    // repaints at all, whatever the poll rate.
    for (var i = 0; i < 10; i++) {
      expect(controller.refreshGuiValues(), 0);
    }
    expect(notified, 0);
    expect(node.guiRevision, 0);

    // One change, one wake — and then quiet again.
    driveFromEngine(node, '2');
    expect(controller.refreshGuiValues(), 1);
    expect(controller.refreshGuiValues(), 0);
    expect(notified, 1);
  });

  test("the body's own push settles without a second repaint", () {
    final node = addPollable(Obj.gSlider);
    controller.setControlValue(node.id, inlet: 0, value: 0.25);
    var notified = 0;
    node.addListener(() => notified++);

    // The push moved `guiValue`, so the first poll after it reports the change
    // (the body is already showing that value, so the repaint is a no-op) —
    // and every poll after it is silent.
    expect(controller.refreshGuiValues(), 1);
    expect(controller.refreshGuiValues(), 0);
    expect(notified, 1);
  });

  test('a body that displays no guiValue is never read', () {
    // A body registered without `readsGuiValue` has no display value that can
    // change from underneath, so polling it would be waste.
    NodeTypeRegistry.instance.register(desc(Obj.gSlider));
    final node = controller.addNode(
      desc: desc(Obj.gSlider),
      position: Offset.zero,
    );
    var notified = 0;
    node.addListener(() => notified++);

    driveFromEngine(node, '1');

    expect(controller.hasGuiValueNodes, isFalse);
    expect(controller.refreshGuiValues(), 0);
    expect(notified, 0);
  });

  test('a .b reports each press over a cable to exactly one poll (issue '
      '#519)', () {
    final node = addPollable(Obj.gButton);
    final values = <String>[];
    node.addListener(() => values.add(controller.guiValueOf(node.id)));

    // An idle button reads `off`, as the engine's does.
    expect(controller.refreshGuiValues(), 1, reason: 'first read: off');
    values.clear();

    // A bang down a cable — a `.metro` tick — with nothing told to Dart.
    gateway.sendBang(controller.instanceId, node.id.value, 0);
    expect(controller.refreshGuiValues(), 1);
    expect(values, ['on'], reason: 'the woken body sees the press');

    // The read consumed it: the next poll reports idle, then nothing more.
    expect(controller.refreshGuiValues(), 1);
    expect(controller.refreshGuiValues(), 0);
    expect(values, ['on', 'off']);

    // The next tick is a new press.
    gateway.sendBang(controller.instanceId, node.id.value, 0);
    expect(controller.refreshGuiValues(), 1);
    expect(values.last, 'on');
  });

  test('a .m reports a message replaced from its inlet, and keeps its '
      'creation args (issue #520)', () {
    final node = addPollable(Obj.gMessage);
    controller.setNodeParams(node.id, '0');
    expect(controller.refreshGuiValues(), 1, reason: 'first read: 0');
    expect(controller.guiValueOf(node.id), '0');

    // A list down a cable — `.pack 1 2 3` — with nothing told to Dart.
    gateway.sendList(controller.instanceId, node.id.value, 0, '1 2 3');
    expect(controller.refreshGuiValues(), 1);
    expect(controller.guiValueOf(node.id), '1 2 3', reason: 'every word');
    expect(controller.refreshGuiValues(), 0, reason: 'nothing new');

    // A click sends the replaced message without changing it, and the
    // arguments the patch saves stay the creation text.
    controller.setControlBang(node.id, inlet: 0);
    expect(controller.guiValueOf(node.id), '1 2 3');
    expect(controller.argsOf(node.id), '0');
  });

  test('an unregistered type is never read', () {
    // Drag-created engine objects fall back to the args body, which renders the
    // creation arguments rather than a live value.
    final sine = gateway.objectTypes().firstWhere((d) => d.type == Obj.dSine);
    final node = controller.addObject(desc: sine, position: Offset.zero);
    driveFromEngine(node, '523.25');

    expect(controller.hasGuiValueNodes, isFalse);
    expect(controller.refreshGuiValues(), 0);
  });

  test('the poll gate follows the nodes in the patch', () {
    expect(controller.hasGuiValueNodes, isFalse);

    final node = addPollable(Obj.gToggle);
    expect(controller.hasGuiValueNodes, isTrue);

    controller.removeNode(node.id);
    expect(controller.hasGuiValueNodes, isFalse);
    // The deleted node's last-seen value went with it, so polling an emptied
    // patch is a clean no-op rather than a read against a dead handle.
    expect(controller.refreshGuiValues(), 0);
  });

  test('only the nodes that actually moved are woken', () {
    final a = addPollable(Obj.gFloat);
    final b = addPollable(Obj.gFloat);
    var wokeA = 0;
    var wokeB = 0;
    a.addListener(() => wokeA++);
    b.addListener(() => wokeB++);

    driveFromEngine(b, '5');

    expect(controller.refreshGuiValues(), 1);
    expect(wokeA, 0);
    expect(wokeB, 1);
  });
}
