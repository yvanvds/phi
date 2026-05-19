import 'package:flutter/widgets.dart';

import '../../domain/patcher/patch_cable.dart';
import '../../domain/patcher/patch_graph.dart';
import '../../domain/patcher/patch_node.dart';
import '../../domain/patcher/patch_node_id.dart';
import '../../domain/patcher/patch_port.dart';
import '../../domain/patcher/patch_port_id.dart';
import '../bridge/patcher_gateway.dart';
import 'node_type_registry.dart';

/// Engine-side mediator between user gestures and the native patcher.
///
/// Owns the [PatchGraph] (Dart-side canvas state) and the
/// [TransformationController] for pan/zoom. Every mutation routes through
/// the [PatcherGateway] first, then updates the graph — so the Dart model
/// only contains nodes the native patcher has accepted.
class PatcherController {
  PatcherController(this._gateway);

  final PatcherGateway _gateway;

  /// The dart-side graph mirror. Listen for add/remove/cable changes.
  final PatchGraph graph = PatchGraph();

  /// Pan/zoom state for the [InteractiveViewer] in the canvas.
  final TransformationController transform = TransformationController();

  // ─── node lifecycle ──────────────────────────────────────────────────

  /// Create a node of [desc.type] at [position] and add it to the graph.
  ///
  /// The native object is created first; its port topology is read back
  /// from `gateway.inspect` so the [PatchNode]'s inlet/outlet shape always
  /// matches what the native side actually has.
  PatchNode addNode({
    required NodeDescriptor desc,
    required Offset position,
    int voice = 1,
  }) {
    final id = _gateway.createObject(desc.type, args: desc.defaultArgs);
    _gateway.setNodePosition(id, position);
    final snapshot = _gateway.inspect(id);
    final node = PatchNode(
      id: PatchNodeId(id),
      type: desc.type,
      title: desc.title,
      voice: voice,
      position: position,
      size: desc.defaultSize,
      inputs: [
        for (var i = 0; i < snapshot.inputs; i++)
          PatchPort(
            index: i,
            side: PatchPortSide.input,
            kind: snapshot.inputKinds[i],
            voice: voice,
          ),
      ],
      outputs: [
        for (var i = 0; i < snapshot.outputs; i++)
          PatchPort(
            index: i,
            side: PatchPortSide.output,
            kind: snapshot.outputKinds[i],
            voice: voice,
          ),
      ],
    );
    graph.addNode(node);
    return node;
  }

  /// Remove a node and any cables touching it.
  void removeNode(PatchNodeId id) {
    final cablesTouching = graph.cables
        .where((c) => c.source.nodeId == id || c.target.nodeId == id)
        .toList();
    for (final c in cablesTouching) {
      _gateway.disconnect(
        fromHandleId: c.source.nodeId.value,
        outlet: c.source.index,
        toHandleId: c.target.nodeId.value,
        inlet: c.target.index,
      );
    }
    _gateway.deleteObject(id.value);
    graph.removeNode(id); // also drops the cables from the Dart side
  }

  /// Move a node by [delta] (canvas-local pixels). Persists to the native
  /// object's GUI properties so a JSON round-trip preserves layout.
  void moveNode(PatchNodeId id, Offset delta) {
    final n = graph.nodeById(id);
    if (n == null) return;
    final next = n.position + delta;
    n.moveTo(next);
    _gateway.setNodePosition(id.value, next);
  }

  // ─── cable lifecycle ─────────────────────────────────────────────────

  void beginCableDrag(PatchPortId from) => graph.beginCableDrag(from);

  void endCableDrag() => graph.endCableDrag();

  /// Connect an output [source] to an input [target]. Rejects malformed
  /// connections (wrong side or unknown id / out-of-range index); accepts
  /// any kind combination since YSE inlets are polymorphic (e.g. `~sine`'s
  /// inlet[0] accepts both a buffer and a float). The native side ignores
  /// messages it can't consume. Returns whether the connection was made.
  bool connect(PatchPortId source, PatchPortId target) {
    if (source.side != PatchPortSide.output) return false;
    if (target.side != PatchPortSide.input) return false;
    final srcNode = graph.nodeById(source.nodeId);
    final dstNode = graph.nodeById(target.nodeId);
    if (srcNode == null || dstNode == null) return false;
    if (source.index >= srcNode.outputs.length) return false;
    if (target.index >= dstNode.inputs.length) return false;
    _gateway.connect(
      fromHandleId: source.nodeId.value,
      outlet: source.index,
      toHandleId: target.nodeId.value,
      inlet: target.index,
    );
    // Cable kind tracks the source port — solid for audio, dashed for
    // control. The destination port's reported kind is informational.
    graph.addCable(
      PatchCable(
        source: source,
        target: target,
        kind: srcNode.outputs[source.index].kind,
      ),
    );
    return true;
  }

  /// Drop a control value into a node's inlet — used by control-object
  /// bodies (`.slider`, `.f`, …) to push their live value into the graph.
  void setControlValue(
    PatchNodeId id, {
    required int inlet,
    required double value,
  }) {
    _gateway.sendFloat(id.value, inlet, value);
  }

  /// Route the patcher's `~dac` output to the master channel so audio is
  /// heard. Must be called after at least one `~dac` exists in the graph;
  /// calling it on an empty patcher crashes the audio thread. Idempotent.
  bool _mounted = false;
  void mountAudio({double volume = 1.0}) {
    if (_mounted) return;
    _gateway.mountAsSound(volume: volume);
    _mounted = true;
  }

  void dispose() {
    transform.dispose();
    graph.dispose();
  }
}
