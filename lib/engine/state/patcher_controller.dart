import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../design/widgets/patcher/patch_canvas_constants.dart';
import '../../domain/patcher/patch_cable.dart';
import '../../domain/patcher/patch_graph.dart';
import '../../domain/patcher/patch_node.dart';
import '../../domain/patcher/patch_node_id.dart';
import '../../domain/patcher/patch_port.dart';
import '../../domain/patcher/patch_port_id.dart';
import '../bridge/patch_object_descriptor.dart';
import '../bridge/patcher_gateway.dart';
import 'node_type_registry.dart';

/// Engine-side mediator between user gestures and the native patcher.
///
/// Owns the [PatchGraph] (Dart-side canvas state) and the
/// [TransformationController] for pan/zoom. Every mutation routes through
/// the [PatcherGateway] first, then updates the graph — so the Dart model
/// only contains nodes the native patcher has accepted.
///
/// One controller drives one gateway instance (one open `patch.` entity,
/// design §8): it creates its [instanceId] on construction and keys every
/// gateway call by it, so a second controller's patcher stays untouched.
class PatcherController {
  PatcherController(this._gateway, {int mainOutputs = 2})
    : instanceId = _gateway.createInstance(mainOutputs: mainOutputs);

  final PatcherGateway _gateway;

  /// This controller's gateway instance — the patcher every op is keyed to.
  final int instanceId;

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
    final id = _gateway.createObject(
      instanceId,
      desc.type,
      args: desc.defaultArgs,
    );
    _gateway.setNodePosition(instanceId, id, position);
    final snapshot = _gateway.inspect(instanceId, id);
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

  /// The engine's full object catalogue as FFI-free descriptors — what the
  /// palette and reference panel render (design §5). Forwards straight to the
  /// gateway's process-wide registry passthrough; the `patcher` (subpatch) type
  /// is already filtered out there (design §10 decision 2).
  List<PatchObjectDescriptor> objectTypes() => _gateway.objectTypes();

  /// Create a node straight from a palette [desc] at [position] — the
  /// **drag-to-create** gesture (design §5).
  ///
  /// Unlike [addNode] (which takes a hand-authored [NodeDescriptor] for the
  /// seeded demo bodies), this creates *any* engine object from its palette
  /// metadata: it seeds the native object with the descriptor's documented
  /// default args, reads the port topology back from `gateway.inspect` (the
  /// native side is authoritative), and sizes the node to fit. The header shows
  /// the object's `type` id (e.g. `~sine`), matching the palette. When the type
  /// has a hand-authored body (the seeded control objects), that body's tuned
  /// [NodeDescriptor.defaultSize] is reused so the live widget fits; otherwise
  /// the box is sized to seat the ports. Per-node live GUI bodies for arbitrary
  /// objects are a later epic issue.
  PatchNode addObject({
    required PatchObjectDescriptor desc,
    required Offset position,
    int voice = 1,
  }) {
    final id = _gateway.createObject(
      instanceId,
      desc.type,
      args: _defaultArgsFor(desc),
    );
    _gateway.setNodePosition(instanceId, id, position);
    final snapshot = _gateway.inspect(instanceId, id);
    final bodied = NodeTypeRegistry.instance.find(desc.type);
    final node = PatchNode(
      id: PatchNodeId(id),
      type: desc.type,
      title: desc.type,
      voice: voice,
      position: position,
      size:
          bodied?.defaultSize ??
          _sizeForPorts(snapshot.inputs, snapshot.outputs),
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

  /// The documented creation-argument string for [desc] — its params' default
  /// values, space-joined. An object with no documented params (e.g. `.slider`,
  /// which registers none and crashes if handed any) yields an empty string.
  String _defaultArgsFor(PatchObjectDescriptor desc) => [
    for (final p in desc.params)
      if (p.defaultValue.isNotEmpty) p.defaultValue,
  ].join(' ');

  /// A node box tall enough to seat its ports (which sit at fixed vertical
  /// spacing measured from the header). One-port minimum so a portless object
  /// still gets a visible body.
  Size _sizeForPorts(int inputs, int outputs) {
    final rows = math.max(1, math.max(inputs, outputs));
    return Size(
      120,
      PatchCanvasConstants.headerHeight +
          PatchCanvasConstants.firstPortOffset +
          rows * PatchCanvasConstants.portSpacing,
    );
  }

  /// Remove a node and any cables touching it.
  void removeNode(PatchNodeId id) {
    final cablesTouching = graph.cables
        .where((c) => c.source.nodeId == id || c.target.nodeId == id)
        .toList();
    for (final c in cablesTouching) {
      _gateway.disconnect(
        instanceId,
        fromHandleId: c.source.nodeId.value,
        outlet: c.source.index,
        toHandleId: c.target.nodeId.value,
        inlet: c.target.index,
      );
    }
    _gateway.deleteObject(instanceId, id.value);
    graph.removeNode(id); // also drops the cables from the Dart side
  }

  /// Move a node by [delta] (canvas-local pixels). Persists to the native
  /// object's GUI properties so a JSON round-trip preserves layout.
  void moveNode(PatchNodeId id, Offset delta) {
    final n = graph.nodeById(id);
    if (n == null) return;
    final next = n.position + delta;
    n.moveTo(next);
    _gateway.setNodePosition(instanceId, id.value, next);
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
      instanceId,
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
    _gateway.sendFloat(instanceId, id.value, inlet, value);
  }

  /// Bang a node's inlet — used by trigger-style control bodies (`.b`, `.t`,
  /// message) to fire into the graph. The `sendBang` companion to
  /// [setControlValue].
  void setControlBang(PatchNodeId id, {required int inlet}) {
    _gateway.sendBang(instanceId, id.value, inlet);
  }

  /// Route the patcher's `~dac` output to a mix bus so audio is heard —
  /// [busChannelId] is the opaque channel id (`null` = master). Must be
  /// called after at least one `~dac` exists in the graph; mounting an empty
  /// patcher crashes the audio thread. Idempotent per bus: re-calling with a
  /// different bus re-mounts, so a placement change follows.
  bool _mounted = false;
  int? _mountedBus;
  void mountAudio({int? busChannelId, double volume = 1.0}) {
    if (_mounted && _mountedBus == busChannelId) return;
    _gateway.mountAsSource(
      instanceId,
      busChannelId: busChannelId,
      volume: volume,
    );
    _mounted = true;
    _mountedBus = busChannelId;
  }

  /// Detach the mounted [Sound], silencing the patcher's source role.
  void unmountAudio() {
    if (!_mounted) return;
    _gateway.unmountSource(instanceId);
    _mounted = false;
    _mountedBus = null;
  }

  void dispose() {
    _gateway.disposeInstance(instanceId);
    transform.dispose();
    graph.dispose();
  }
}
