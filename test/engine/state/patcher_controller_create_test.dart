import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:yse/yse.dart';

import '../test_doubles/fake_patcher_gateway.dart';

/// Object creation as a **journaled** verb (issue #358).
///
/// Creation was the one canvas verb that stayed off the undo stack: move,
/// connect, delete, duplicate and re-param all round-trip under Ctrl+Z, so an
/// object that could not be un-created was the odd one out — and the typing
/// gesture, which mints objects a keystroke at a time, makes that gap
/// impossible to live with. These cover the controller half: the object reaches
/// the native side, an undo takes it away there too, and a redo brings it back
/// under the *same* logical id so anything that named it stays valid.
void main() {
  late FakePatcherGateway gateway;
  late PatcherController controller;

  setUp(() {
    gateway = FakePatcherGateway();
    controller = PatcherController(gateway);
  });

  tearDown(() => controller.dispose());

  Iterable<String> createCalls() =>
      gateway.calls.where((c) => c.startsWith('createObject:'));

  test('createObject mints the object with its documented defaults', () {
    final sine = gateway.objectTypes().firstWhere((d) => d.type == Obj.dSine);

    final id = controller.createObject(
      desc: sine,
      position: const Offset(40, 60),
    );

    expect(id, isNotNull);
    expect(controller.graph.nodes, hasLength(1));
    expect(controller.argsOf(id!), '440');
    expect(controller.graph.nodeById(id)!.position, const Offset(40, 60));
    expect(gateway.nodes.values.single.args, '440');
  });

  test('explicit args win over the documented defaults', () {
    final sine = gateway.objectTypes().firstWhere((d) => d.type == Obj.dSine);

    final id = controller.createObject(
      desc: sine,
      position: Offset.zero,
      args: '220',
    );

    expect(controller.argsOf(id!), '220');
    expect(gateway.nodes.values.single.args, '220');
  });

  test('the fresh object becomes the selection', () {
    final sine = gateway.objectTypes().firstWhere((d) => d.type == Obj.dSine);

    final id = controller.createObject(desc: sine, position: Offset.zero);

    // So the hand that just typed it can move, duplicate or delete it without
    // reaching for the mouse.
    expect(controller.graph.selectedNodes, {id});
  });

  test('undo removes it from the graph *and* the native patcher', () {
    final sine = gateway.objectTypes().firstWhere((d) => d.type == Obj.dSine);
    final id = controller.createObject(desc: sine, position: Offset.zero);

    controller.undo();

    expect(controller.graph.nodes, isEmpty);
    expect(gateway.nodes, isEmpty);
    // …and the selection went with it.
    expect(controller.graph.selectedNodes, isEmpty);
    expect(controller.graph.nodeById(id!), isNull);
  });

  test('redo brings it back under the same logical id, args intact', () {
    final sine = gateway.objectTypes().firstWhere((d) => d.type == Obj.dSine);
    final id = controller.createObject(
      desc: sine,
      position: const Offset(80, 90),
      args: '220',
    );

    controller.undo();
    controller.redo();

    // The same logical id — a fresh native handle behind it, but every cable and
    // lower undo command that named this node stays valid.
    expect(controller.graph.nodes, hasLength(1));
    expect(controller.graph.nodes.single.id, id);
    expect(controller.argsOf(id!), '220');
    expect(controller.graph.nodeById(id)!.position, const Offset(80, 90));
    expect(gateway.nodes.values.single.args, '220');
    expect(controller.graph.selectedNodes, {id});
  });

  test('an undo/redo cycle does not accumulate objects', () {
    final sine = gateway.objectTypes().firstWhere((d) => d.type == Obj.dSine);
    controller.createObject(desc: sine, position: Offset.zero);

    for (var i = 0; i < 3; i++) {
      controller.undo();
      controller.redo();
    }

    expect(controller.graph.nodes, hasLength(1));
    expect(gateway.nodes, hasLength(1));
    // Four creates in total: the original plus one per redo — never two at once.
    expect(createCalls(), hasLength(4));
  });

  test('addObject stays the direct primitive — nothing journaled', () {
    final sine = gateway.objectTypes().firstWhere((d) => d.type == Obj.dSine);

    controller.addObject(desc: sine, position: Offset.zero);

    expect(controller.graph.nodes, hasLength(1));
    expect(controller.undoScope.canUndo, isFalse);
  });
}
