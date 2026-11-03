import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:yse/yse.dart';

/// Encapsulate and de-encapsulate (issue #552) against the real engine: the
/// moves the editor makes ([PatcherController.setContainerPrimitive] over live,
/// connected objects) and the cables it re-wires through the new pins are what
/// libYSE ends up holding — read back from a dump of the patch, not from the
/// editor's own mirror — and the patch still renders.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RealPatcherGateway gateway;
  late PatcherController controller;
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

  setUp(() {
    gateway = RealPatcherGateway();
    controller = PatcherController(gateway);
  });

  tearDown(() {
    controller.dispose();
    gateway.disposeAll();
  });

  PatchNodeId make(String type, {String args = '', Offset at = Offset.zero}) {
    final desc = controller.objectTypes().firstWhere((d) => d.type == type);
    return controller.createObject(desc: desc, position: at, args: args)!;
  }

  PatchPortId inlet(PatchNodeId id, [int i = 0]) =>
      PatchPortId(nodeId: id, side: PatchPortSide.input, index: i);
  PatchPortId outlet(PatchNodeId id, [int i = 0]) =>
      PatchPortId(nodeId: id, side: PatchPortSide.output, index: i);

  /// The patch as the engine saves it, loaded into a fresh editor.
  PatcherController reloaded() {
    final copy = gateway.createInstance();
    gateway.parseJson(copy, gateway.dumpJson(controller.instanceId));
    return PatcherController.bound(gateway, instanceId: copy)
      ..rebuildFromInstance();
  }

  /// Every cable of [editor], by the types at its displayed ends.
  Set<String> wiringOf(PatcherController editor) => {
    for (final c in editor.graph.cables)
      '${editor.graph.nodeById(editor.displayPort(c.source).nodeId)!.type}'
          ':${editor.displayPort(c.source).index}'
          '->${editor.graph.nodeById(editor.displayPort(c.target).nodeId)!.type}'
          ':${editor.displayPort(c.target).index}',
  };

  void render() {
    controller.mountAudio();
    System.instance.renderOffline(1);
    System.instance.update();
  }

  test('encapsulate, undo, redo and de-encapsulate reach the engine', () {
    final src = make(Obj.dSine, args: '220');
    final slider = make(Obj.gSlider, at: const Offset(200, 0));
    final sine = make(Obj.dSine, args: '440', at: const Offset(0, 120));
    final dac = make(Obj.dDac, at: const Offset(0, 300));
    expect(controller.connectViaGesture(outlet(src), inlet(sine)), isTrue);
    expect(controller.connectViaGesture(outlet(slider), inlet(sine)), isTrue);
    expect(controller.connectViaGesture(outlet(sine), inlet(dac)), isTrue);
    final flat = wiringOf(reloaded());
    expect(flat, {'~sine:0->~sine:0', '.slider:0->~sine:0', '~sine:0->~dac:0'});
    render();

    controller.selectNodes({sine});
    final box = controller.encapsulateSelection()!;

    var copy = reloaded();
    final reloadedBox = copy.graph.nodes.singleWhere(
      (n) => n.type == Obj.patcher,
    );
    expect(reloadedBox.inputs.map((p) => p.kind), [
      PatchPortKind.audio,
      PatchPortKind.control,
    ]);
    expect(reloadedBox.outputs.map((p) => p.kind), [PatchPortKind.audio]);
    expect(copy.nodesIn(reloadedBox.id).map((n) => n.type).toSet(), {
      Obj.dInlet,
      Obj.gInlet,
      Obj.dSine,
      Obj.dOutlet,
    });
    expect(wiringOf(copy), {
      '~sine:0->patcher:0',
      '.slider:0->patcher:1',
      '~inlet:0->~sine:0',
      '.inlet:0->~sine:0',
      '~sine:0->~outlet:0',
      'patcher:0->~dac:0',
    });
    copy.dispose();
    render();

    controller.undo();
    copy = reloaded();
    expect(copy.graph.nodes.any((n) => n.type == Obj.patcher), isFalse);
    expect(wiringOf(copy), flat);
    copy.dispose();

    controller.redo();
    copy = reloaded();
    expect(copy.graph.nodes.where((n) => n.type == Obj.patcher), hasLength(1));
    expect(wiringOf(copy), contains('patcher:0->~dac:0'));
    copy.dispose();
    render();

    controller
      ..selectNodes({box})
      ..deencapsulateSelection();
    copy = reloaded();
    expect(copy.graph.nodes.map((n) => n.type).toSet(), {
      Obj.dSine,
      Obj.gSlider,
      Obj.dDac,
    });
    expect(copy.graph.nodes.every((n) => n.container == null), isTrue);
    expect(wiringOf(copy), flat);
    copy.dispose();
    render();
  });
}
