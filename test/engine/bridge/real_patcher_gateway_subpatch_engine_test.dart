import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:yse/yse.dart';

/// Subpatches through [RealPatcherGateway] against the real engine (issue
/// #481): containment, the pins a box reads off its boundary objects, the
/// cable the engine records on a boundary object, and a dump → parse round
/// trip that keeps all three.
void main() {
  late RealPatcherGateway gateway;
  var engineUp = false;

  setUpAll(() {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
    engineUp = true;
  });

  tearDownAll(() {
    if (engineUp) System.instance.close();
  });

  setUp(() => gateway = RealPatcherGateway());
  tearDown(() => gateway.disposeAll());

  test('the catalogue offers the subpatcher', () {
    expect(gateway.objectTypes().map((d) => d.type), contains(Obj.patcher));
  });

  test('a box reads its pins and their kinds off its boundary objects', () {
    final inst = gateway.createInstance();
    final box = gateway.createObject(inst, Obj.patcher, args: 'gain');
    expect(gateway.inspect(inst, box).inputs, 0);

    for (final (type, args) in [
      (Obj.dInlet, '0'),
      (Obj.gInlet, '1'),
      (Obj.dOutlet, '0'),
    ]) {
      final h = gateway.createObject(inst, type, args: args);
      gateway.setContainer(inst, h, box);
    }

    final pins = gateway.inspect(inst, box);
    expect(pins.inputs, 2);
    expect(pins.inputKinds, [PatchPortKind.audio, PatchPortKind.control]);
    expect(pins.outputs, 1);
    expect(pins.outputKinds, [PatchPortKind.audio]);
  });

  test('enumerate reports containment and the cable on the boundary', () {
    final inst = gateway.createInstance();
    final box = gateway.createObject(inst, Obj.patcher);
    final inlet = gateway.createObject(inst, Obj.dInlet, args: '0');
    gateway.setContainer(inst, inlet, box);
    final sine = gateway.createObject(inst, Obj.dSine, args: '440');
    gateway.connect(
      inst,
      fromHandleId: sine,
      outlet: 0,
      toHandleId: inlet,
      inlet: 0,
    );

    final graph = gateway.enumerate(inst);
    final byId = {for (final o in graph.objects) o.handleId: o};
    expect(byId[inlet]!.container, box);
    expect(byId[sine]!.container, isNull);
    expect(byId[box]!.ports.inputs, 1);
    final cable = graph.connections.single;
    expect(
      (cable.fromHandleId, cable.toHandleId, cable.inlet),
      (sine, inlet, 0),
    );
  });

  test('deleting a box takes its contents out of the handle table', () {
    final inst = gateway.createInstance();
    final box = gateway.createObject(inst, Obj.patcher);
    final inner = gateway.createObject(inst, Obj.dSine);
    gateway.setContainer(inst, inner, box);
    final keep = gateway.createObject(inst, Obj.dDac);

    gateway.deleteObject(inst, box);

    expect(gateway.enumerate(inst).objects.map((o) => o.handleId), [keep]);
  });

  test('a dump → parse round trip keeps the tree and its cables', () {
    final inst = gateway.createInstance();
    final box = gateway.createObject(inst, Obj.patcher, args: 'gain');
    final inlet = gateway.createObject(inst, Obj.gInlet, args: '0');
    final outlet = gateway.createObject(inst, Obj.gOutlet, args: '0');
    gateway
      ..setContainer(inst, inlet, box)
      ..setContainer(inst, outlet, box)
      ..connect(
        inst,
        fromHandleId: inlet,
        outlet: 0,
        toHandleId: outlet,
        inlet: 0,
      );

    final copy = gateway.createInstance();
    gateway.parseJson(copy, gateway.dumpJson(inst));

    final objects = gateway.enumerate(copy).objects;
    final reloadedBox = objects.singleWhere((o) => o.type == Obj.patcher);
    expect(reloadedBox.args, 'gain');
    expect(reloadedBox.ports.inputs, 1);
    expect(reloadedBox.ports.outputs, 1);
    expect(
      objects.where((o) => o.container == reloadedBox.handleId),
      hasLength(2),
    );
    expect(gateway.enumerate(copy).connections, hasLength(1));
  });

  test('a refused move throws', () {
    final inst = gateway.createInstance();
    final notABox = gateway.createObject(inst, Obj.dSine);
    final obj = gateway.createObject(inst, Obj.dDac);
    expect(
      () => gateway.setContainer(inst, obj, notABox),
      throwsA(isA<YseException>()),
    );
  });
}
