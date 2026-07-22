import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:yse/yse.dart';

import '../test_doubles/fake_patcher_gateway.dart';

/// Unit coverage for `PatcherController.rebuildFromInstance` (issue #308): a
/// bound editor over a live native instance reconstructs its whole Dart-side
/// mirror (nodes, ports, args, positions and cables) so a patch opened from a
/// reloaded dump — or re-materialised by a rename — shows its graph instead of
/// an empty canvas.
///
/// The node-type registry is cleared in setUp so no hand-authored body's title /
/// size interferes — the reconstruction is asserted against the type-driven
/// fallbacks.
void main() {
  late FakePatcherGateway gateway;

  setUp(() {
    gateway = FakePatcherGateway();
    NodeTypeRegistry.instance.clear();
  });

  /// Build a slider → sine → dac graph directly on a fresh instance (as the
  /// reconciler's `parseJson` would), returning the instance id + handles.
  ({int instanceId, int slider, int sine, int dac}) seedInstance() {
    final instanceId = gateway.createInstance(mainOutputs: 1);
    final slider = gateway.createObject(instanceId, Obj.gSlider);
    final sine = gateway.createObject(instanceId, Obj.dSine, args: '440');
    final dac = gateway.createObject(instanceId, Obj.dDac);
    gateway.setNodePosition(instanceId, slider, const Offset(20, 40));
    gateway.setNodePosition(instanceId, sine, const Offset(200, 40));
    gateway.setNodePosition(instanceId, dac, const Offset(380, 40));
    gateway.connect(
      instanceId,
      fromHandleId: slider,
      outlet: 0,
      toHandleId: sine,
      inlet: 0,
    );
    gateway.connect(
      instanceId,
      fromHandleId: sine,
      outlet: 0,
      toHandleId: dac,
      inlet: 0,
    );
    return (instanceId: instanceId, slider: slider, sine: sine, dac: dac);
  }

  test('reconstructs nodes with type, position, ports and args', () {
    final s = seedInstance();
    final editor = PatcherController.bound(gateway, instanceId: s.instanceId);
    addTearDown(editor.dispose);

    editor.rebuildFromInstance();

    expect(editor.graph.nodes, hasLength(3));

    final sine = editor.graph.nodeById(PatchNodeId(s.sine))!;
    expect(sine.type, Obj.dSine);
    expect(sine.title, Obj.dSine); // no body registered → type is the title
    expect(sine.position, const Offset(200, 40));
    expect(sine.inputs.single.kind, PatchPortKind.control);
    expect(sine.outputs.single.kind, PatchPortKind.audio);
    expect(editor.argsOf(sine.id), '440');

    final dac = editor.graph.nodeById(PatchNodeId(s.dac))!;
    expect(dac.inputs, hasLength(2)); // ~dac has two audio inlets
  });

  test('reconstructs cables with the source outlet kind', () {
    final s = seedInstance();
    final editor = PatcherController.bound(gateway, instanceId: s.instanceId);
    addTearDown(editor.dispose);

    editor.rebuildFromInstance();

    final cables = editor.graph.cables;
    expect(cables, hasLength(2));
    final toDac = cables.firstWhere(
      (c) => c.target.nodeId == PatchNodeId(s.dac),
    );
    expect(toDac.source.nodeId, PatchNodeId(s.sine));
    expect(toDac.source.index, 0);
    expect(toDac.target.index, 0);
    // sine's outlet is audio, so the cable is drawn as an audio cable.
    expect(toDac.kind, PatchPortKind.audio);
  });

  test('does not re-issue native connects for reconstructed cables', () {
    final s = seedInstance();
    final connectsBefore = gateway.calls
        .where((c) => c.startsWith('connect:'))
        .length;
    final editor = PatcherController.bound(gateway, instanceId: s.instanceId);
    addTearDown(editor.dispose);

    editor.rebuildFromInstance();

    // The native connections already exist — rebuilding must not double them.
    final connectsAfter = gateway.calls
        .where((c) => c.startsWith('connect:'))
        .length;
    expect(connectsAfter, connectsBefore);
    // And the live gateway still holds exactly the two seeded cables.
    expect(gateway.instances[s.instanceId]!.cables, hasLength(2));
  });

  test('is idempotent — a second rebuild does not double the graph', () {
    final s = seedInstance();
    final editor = PatcherController.bound(gateway, instanceId: s.instanceId);
    addTearDown(editor.dispose);

    editor.rebuildFromInstance();
    editor.rebuildFromInstance();

    expect(editor.graph.nodes, hasLength(3));
    expect(editor.graph.cables, hasLength(2));
  });

  test('wires _nativeByNode so a later edit reaches the right handle', () {
    final s = seedInstance();
    final editor = PatcherController.bound(gateway, instanceId: s.instanceId);
    addTearDown(editor.dispose);
    editor.rebuildFromInstance();

    // A control value pushed to the reconstructed slider node must land on its
    // native handle — proof the id map was rebuilt, not just the visuals.
    editor.setControlValue(PatchNodeId(s.slider), inlet: 0, value: 0.5);
    expect(
      gateway.instances[s.instanceId]!.nodes[s.slider]!.lastValueByInlet[0],
      0.5,
    );
  });

  test('an empty instance rebuilds to an empty graph', () {
    final instanceId = gateway.createInstance(mainOutputs: 1);
    final editor = PatcherController.bound(gateway, instanceId: instanceId);
    addTearDown(editor.dispose);

    editor.rebuildFromInstance();

    expect(editor.graph.nodes, isEmpty);
    expect(editor.graph.cables, isEmpty);
  });
}
