import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../design/widgets/patcher/patch_canvas_constants.dart';
import '../../domain/patcher/patch_cable.dart';
import '../../domain/patcher/patch_graph.dart';
import '../../domain/patcher/patch_node.dart';
import '../../domain/patcher/patch_node_id.dart';
import '../../domain/patcher/patch_port.dart';
import '../../domain/patcher/patch_port_id.dart';
import '../../domain/patcher/patch_port_kind.dart';
import '../../domain/project/undo_scope.dart';
import '../bridge/patch_object_descriptor.dart';
import '../bridge/patch_pin_compatibility.dart';
import '../bridge/patcher_gateway.dart';
import 'node_type_registry.dart';
import 'patch_node_spec.dart';
import 'patcher_commands/connect_cable_command.dart';
import 'patcher_commands/delete_cable_command.dart';
import 'patcher_commands/delete_patch_nodes_command.dart';
import 'patcher_commands/duplicate_patch_selection_command.dart';
import 'patcher_commands/move_patch_nodes_command.dart';
import 'patcher_commands/set_patch_params_command.dart';

/// Engine-side mediator between user gestures and the native patcher.
///
/// Owns the [PatchGraph] (Dart-side canvas state) and the
/// [TransformationController] for pan/zoom. Every mutation routes through
/// the [PatcherGateway] first, then updates the graph — so the Dart model
/// only contains nodes the native patcher has accepted.
///
/// Canvas gestures (body drag, connect, delete, duplicate) are journaled onto
/// a per-surface [undoScope] as `ProjectCommand`s, so Ctrl+Z/Y walk them in
/// human-sized steps (design `docs/design/patcher.md` §6). A node's stable
/// [PatchNodeId] is decoupled from its (churning) native handle by
/// [_nativeByNode], so a delete can be undone — the object comes back under a
/// *fresh* native handle but the **same** logical id, keeping cables and any
/// lower undo commands that named it valid.
///
/// One controller drives one gateway instance (one open `patch.` entity,
/// design §8): it keys every gateway call by its [instanceId], so a second
/// controller's patcher stays untouched.
///
/// Two ways to obtain the instance. The default constructor **creates** a fresh
/// native patcher and owns it — [dispose] tears it down. [PatcherController.bound]
/// instead **binds** to an instance minted elsewhere (the [PatchReconciler]'s
/// per-entity patcher, issue #224): the editor edits that live instance without
/// owning it, so [dispose] leaves the native patcher to the reconciler that
/// created it.
class PatcherController {
  PatcherController(this._gateway, {int mainOutputs = 2, String name = ''})
    : instanceId = _gateway.createInstance(
        mainOutputs: mainOutputs,
        name: name,
      ),
      _ownsInstance = true;

  /// Bind an editor to an already-created gateway [instanceId] (the reconciler's
  /// per-entity patcher). The controller drives edits on it but does **not** own
  /// it: [dispose] frees only the Dart-side resources, leaving the native patcher
  /// to whoever minted the instance.
  PatcherController.bound(this._gateway, {required this.instanceId})
    : _ownsInstance = false;

  final PatcherGateway _gateway;

  /// This controller's gateway instance — the patcher every op is keyed to.
  final int instanceId;

  /// Whether this controller created (and therefore disposes) its [instanceId].
  /// `false` for a [PatcherController.bound] editor over a reconciler instance.
  final bool _ownsInstance;

  /// The dart-side graph mirror. Listen for add/remove/cable/selection changes.
  final PatchGraph graph = PatchGraph();

  /// Pan/zoom state for the [InteractiveViewer] in the canvas.
  final TransformationController transform = TransformationController();

  /// This surface's undo/redo stack — the patcher scope in the undo-follows-
  /// focus model. Canvas gestures `run` a command here; the canvas routes
  /// Ctrl+Z/Y to [undo]/[redo].
  final UndoScope undoScope = UndoScope(id: 'patcher', label: 'Patcher');

  /// Logical node id → current native handle. Rebuilt on restore so a logical
  /// id outlives the native object it names.
  final Map<PatchNodeId, int> _nativeByNode = {};

  /// Logical node id → the creation-argument string it was made with — captured
  /// so a delete's undo (and a duplicate) recreate the object identically.
  final Map<PatchNodeId, String> _argsByNode = {};

  /// Falls below zero to mint collision-free logical ids when a native handle
  /// value is already in use (only possible if the native side reuses handles).
  int _syntheticFloor = -1;

  /// Origin positions captured at the start of a body drag, so the release can
  /// journal one move command for the whole gesture.
  final Map<PatchNodeId, Offset> _dragStart = {};

  Map<String, PatchObjectDescriptor>? _catalogueCache;
  Map<String, PatchObjectDescriptor> get _catalogue =>
      _catalogueCache ??= {for (final d in _gateway.objectTypes()) d.type: d};

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
    return _create(
      type: desc.type,
      args: desc.defaultArgs,
      title: desc.title,
      voice: voice,
      position: position,
      size: desc.defaultSize,
    );
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
  /// default args and sizes the node to fit (reusing a hand-authored body's
  /// tuned size when the type has one). The header shows the object's `type` id.
  PatchNode addObject({
    required PatchObjectDescriptor desc,
    required Offset position,
    int voice = 1,
  }) {
    final bodied = NodeTypeRegistry.instance.find(desc.type);
    return _create(
      type: desc.type,
      args: _defaultArgsFor(desc),
      title: desc.type,
      voice: voice,
      position: position,
      size: bodied?.defaultSize, // null → sized to fit the reified ports
    );
  }

  /// Shared node creation: mint the native object, key it to a fresh logical
  /// id, persist its position, reify its ports, and add it to the graph.
  PatchNode _create({
    required String type,
    required String args,
    required String title,
    required int voice,
    required Offset position,
    Size? size,
  }) {
    final native = _gateway.createObject(instanceId, type, args: args);
    final id = _mintLogicalId(native);
    _nativeByNode[id] = native;
    _argsByNode[id] = args;
    _gateway.setNodePosition(instanceId, native, position);
    final snapshot = _gateway.inspect(instanceId, native);
    final node = PatchNode(
      id: id,
      type: type,
      title: title,
      voice: voice,
      position: position,
      size: size ?? _sizeForPorts(snapshot.inputs, snapshot.outputs),
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

  // ─── graph reconstruction (from a reloaded / re-materialised instance) ──

  /// Rebuild the Dart-side mirror ([graph], [_nativeByNode], [_argsByNode]) from
  /// the live native instance (issue #308).
  ///
  /// A [PatcherController.bound] editor starts with an empty [graph], so a patch
  /// **loaded from disk** — its dump already `parseJson`'d into the native
  /// instance by the reconciler — or one whose native instance was re-materialised
  /// by a rename shows a blank canvas until it is edited. This enumerates the
  /// instance ([PatcherGateway.enumerate]) and reconstructs every node and cable
  /// from it, so opening such a patch shows its graph at once.
  ///
  /// The native objects and connections **already exist** (the reconciler built
  /// them), so cables are wired straight into the mirror — no gateway `connect`
  /// is re-issued. Any prior mirror state is dropped first, so it is safe to call
  /// on a non-empty editor. Node voice is not carried in the dump, so every
  /// reconstructed node defaults to voice 1.
  void rebuildFromInstance() {
    for (final id in _nativeByNode.keys.toList()) {
      graph.removeNode(id);
    }
    _nativeByNode.clear();
    _argsByNode.clear();

    final snapshot = _gateway.enumerate(instanceId);
    for (final obj in snapshot.objects) {
      final id = PatchNodeId(obj.handleId);
      _nativeByNode[id] = obj.handleId;
      _argsByNode[id] = obj.args;
      final bodied = NodeTypeRegistry.instance.find(obj.type);
      final ports = obj.ports;
      graph.addNode(
        PatchNode(
          id: id,
          type: obj.type,
          title: bodied?.title ?? obj.type,
          voice: 1,
          position: obj.position ?? Offset.zero,
          size:
              bodied?.defaultSize ?? _sizeForPorts(ports.inputs, ports.outputs),
          inputs: [
            for (var i = 0; i < ports.inputs; i++)
              PatchPort(
                index: i,
                side: PatchPortSide.input,
                kind: ports.inputKinds[i],
                voice: 1,
              ),
          ],
          outputs: [
            for (var i = 0; i < ports.outputs; i++)
              PatchPort(
                index: i,
                side: PatchPortSide.output,
                kind: ports.outputKinds[i],
                voice: 1,
              ),
          ],
        ),
      );
    }

    // Wire cables straight into the mirror — the native connections already
    // exist, so re-issuing `connect` would double them.
    for (final conn in snapshot.connections) {
      final srcId = PatchNodeId(conn.fromHandleId);
      final srcNode = graph.nodeById(srcId);
      if (srcNode == null || conn.outlet >= srcNode.outputs.length) continue;
      if (graph.nodeById(PatchNodeId(conn.toHandleId)) == null) continue;
      graph.addCable(
        PatchCable(
          source: PatchPortId(
            nodeId: srcId,
            side: PatchPortSide.output,
            index: conn.outlet,
          ),
          target: PatchPortId(
            nodeId: PatchNodeId(conn.toHandleId),
            side: PatchPortSide.input,
            index: conn.inlet,
          ),
          kind: srcNode.outputs[conn.outlet].kind,
        ),
      );
    }
  }

  /// A logical id equal to the native handle when free, else a synthetic
  /// negative id that can never collide with a native (non-negative) handle.
  PatchNodeId _mintLogicalId(int native) {
    final direct = PatchNodeId(native);
    if (!_nativeByNode.containsKey(direct)) return direct;
    return PatchNodeId(_syntheticFloor--);
  }

  /// Remove a node and any cables touching it. Direct (non-undoable) — used by
  /// programmatic teardown; the canvas deletes through [deleteSelection].
  void removeNode(PatchNodeId id) {
    final cablesTouchingIt = graph.cables
        .where((c) => c.source.nodeId == id || c.target.nodeId == id)
        .toList();
    for (final c in cablesTouchingIt) {
      removeCablePrimitive(c);
    }
    deleteNodePrimitive(id);
  }

  /// Move a node by [delta] (canvas-local pixels). Direct (non-undoable);
  /// persists to the native object's GUI properties so a JSON round-trip
  /// preserves layout.
  void moveNode(PatchNodeId id, Offset delta) {
    final n = graph.nodeById(id);
    if (n == null) return;
    placeNode(id, n.position + delta);
  }

  // ─── cable lifecycle ─────────────────────────────────────────────────

  void beginCableDrag(PatchPortId from) => graph.beginCableDrag(from);

  void endCableDrag() => graph.endCableDrag();

  /// Connect an output [source] to an input [target]. Rejects malformed
  /// connections (wrong side or unknown id / out-of-range index); accepts
  /// any kind combination since YSE inlets are polymorphic (e.g. `~sine`'s
  /// inlet[0] accepts both a buffer and a float). The native side ignores
  /// messages it can't consume. Returns whether the connection was made.
  ///
  /// This is the permissive low-level connect used by the seed and any
  /// programmatic wiring. The canvas authoring gesture goes through
  /// [connectViaGesture], which additionally enforces typed-pin compatibility.
  bool connect(PatchPortId source, PatchPortId target) {
    final cable = _cableFor(source, target);
    if (cable == null) return false;
    addCablePrimitive(cable);
    return true;
  }

  /// Structural validity + a built [PatchCable] (kind from the source outlet),
  /// or null when the endpoints are malformed. No typed-pin gate here.
  PatchCable? _cableFor(PatchPortId source, PatchPortId target) {
    if (source.side != PatchPortSide.output) return null;
    if (target.side != PatchPortSide.input) return null;
    final srcNode = graph.nodeById(source.nodeId);
    final dstNode = graph.nodeById(target.nodeId);
    if (srcNode == null || dstNode == null) return null;
    if (source.index >= srcNode.outputs.length) return null;
    if (target.index >= dstNode.inputs.length) return null;
    return PatchCable(
      source: source,
      target: target,
      kind: srcNode.outputs[source.index].kind,
    );
  }

  /// Drop a control value into a node's inlet — used by control-object
  /// bodies (`.slider`, `.f`, …) to push their live value into the graph.
  void setControlValue(
    PatchNodeId id, {
    required int inlet,
    required double value,
  }) {
    final native = _nativeByNode[id];
    if (native == null) return;
    _gateway.sendFloat(instanceId, native, inlet, value);
  }

  /// Bang a node's inlet — used by trigger-style control bodies (`.b`, `.t`,
  /// message) to fire into the graph. The `sendBang` companion to
  /// [setControlValue].
  void setControlBang(PatchNodeId id, {required int inlet}) {
    final native = _nativeByNode[id];
    if (native == null) return;
    _gateway.sendBang(instanceId, native, inlet);
  }

  /// The live GUI display value of a node (`guiValue`) — what a control body
  /// (`.slider`, `.f`, `.i`, `.t`) shows. Empty for a node with no native
  /// handle or no display value.
  String guiValueOf(PatchNodeId id) {
    final native = _nativeByNode[id];
    if (native == null) return '';
    return _gateway.guiValue(instanceId, native);
  }

  /// The creation-argument string a node was last made / reconfigured with —
  /// what the params dialog seeds its fields from and what
  /// [SetPatchParamsCommand] captures for undo.
  String argsOf(PatchNodeId id) => _argsByNode[id] ?? '';

  // ─── typed-pin queries (drag-time compatibility) ─────────────────────

  /// The data type an outlet emits (`OutType`), read from the object catalogue
  /// and falling back to the reified port kind for uncatalogued types.
  PatchOutletType outletTypeOf(PatchPortId source) {
    final node = graph.nodeById(source.nodeId);
    if (node == null) return PatchOutletType.invalid;
    final desc = _catalogue[node.type];
    if (desc != null && source.index < desc.outlets.length) {
      return desc.outlets[source.index].type;
    }
    if (source.index < node.outputs.length) {
      return node.outputs[source.index].kind == PatchPortKind.audio
          ? PatchOutletType.buffer
          : PatchOutletType.float;
    }
    return PatchOutletType.invalid;
  }

  /// The message kinds an inlet accepts, from the catalogue (falling back to
  /// the reified port kind for uncatalogued types).
  Set<PatchInletAccept> inletAcceptsOf(PatchPortId target) {
    final node = graph.nodeById(target.nodeId);
    if (node == null) return const {};
    final desc = _catalogue[node.type];
    if (desc != null && target.index < desc.inlets.length) {
      return desc.inlets[target.index].accepts;
    }
    if (target.index < node.inputs.length) {
      return node.inputs[target.index].kind == PatchPortKind.audio
          ? const {PatchInletAccept.buffer}
          : const {
              PatchInletAccept.float,
              PatchInletAccept.integer,
              PatchInletAccept.bang,
              PatchInletAccept.list,
            };
    }
    return const {};
  }

  /// Whether a cable from [source] to [target] is a *legal authoring gesture*:
  /// structurally sound, not a self-wire, not a duplicate, and typed-pin
  /// compatible ([patchPinsCompatible]). Drives inlet highlighting and drop
  /// acceptance — unlike [connect], which is deliberately permissive.
  bool canConnect(PatchPortId source, PatchPortId target) {
    if (source.side != PatchPortSide.output) return false;
    if (target.side != PatchPortSide.input) return false;
    if (source.nodeId == target.nodeId) return false;
    final srcNode = graph.nodeById(source.nodeId);
    final dstNode = graph.nodeById(target.nodeId);
    if (srcNode == null || dstNode == null) return false;
    if (source.index >= srcNode.outputs.length) return false;
    if (target.index >= dstNode.inputs.length) return false;
    final already = graph.cables.any(
      (c) => c.source == source && c.target == target,
    );
    if (already) return false;
    return patchPinsCompatible(outletTypeOf(source), inletAcceptsOf(target));
  }

  // ─── selection ───────────────────────────────────────────────────────

  /// Select a single node — or, with [additive] (shift-click), toggle its
  /// membership in the current selection.
  void selectNode(PatchNodeId id, {bool additive = false}) =>
      additive ? graph.toggleNode(id) : graph.selectNodes({id});

  void selectNodes(Set<PatchNodeId> ids) => graph.selectNodes(ids);

  void selectCable(PatchCable cable) => graph.selectCable(cable);

  void clearSelection() => graph.clearSelection();

  // ─── gesture entry points (journaled onto [undoScope]) ───────────────

  /// Start a body drag from [primary]. If [primary] isn't already selected it
  /// becomes the sole selection; the whole selection then drags together.
  void beginNodeDrag(PatchNodeId primary) {
    if (!graph.isNodeSelected(primary)) graph.selectNodes({primary});
    _dragStart
      ..clear()
      ..addEntries(
        graph.selectedNodes.map(
          (id) => MapEntry(id, graph.nodeById(id)?.position ?? Offset.zero),
        ),
      );
  }

  /// Preview the in-flight drag by shifting every dragged node live — no
  /// gateway write, no command; the release commits one [MovePatchNodesCommand].
  void dragSelectedBy(Offset delta) {
    for (final id in _dragStart.keys) {
      final n = graph.nodeById(id);
      if (n != null) n.moveTo(n.position + delta);
    }
  }

  /// Abandon an in-flight body drag: put every dragged node back where the
  /// press found it and journal **nothing**.
  ///
  /// [endNodeDrag]'s counterpart for a gesture that never gets its release — a
  /// cancelled pointer (the window loses capture, a system drag takes over).
  /// Such a gesture is not an edit the user made, so committing the half-move
  /// it happened to reach would both leave the nodes somewhere nobody chose and
  /// put a step on the undo stack that never happened (issue #355). Safe to
  /// call with no drag in flight.
  void abortNodeDrag() {
    if (_dragStart.isEmpty) return;
    _dragStart.forEach((id, start) => graph.nodeById(id)?.moveTo(start));
    _dragStart.clear();
  }

  /// Commit the body drag: journal one move for the whole selection (nothing
  /// when the net movement is zero).
  void endNodeDrag() {
    if (_dragStart.isEmpty) return;
    final from = <PatchNodeId, Offset>{};
    final to = <PatchNodeId, Offset>{};
    var moved = false;
    _dragStart.forEach((id, start) {
      final n = graph.nodeById(id);
      if (n == null) return;
      from[id] = start;
      to[id] = n.position;
      if (n.position != start) moved = true;
    });
    _dragStart.clear();
    if (!moved) return;
    undoScope.run(MovePatchNodesCommand(this, from: from, to: to));
  }

  /// Author a cable from the canvas (design §6). Returns false — leaving the
  /// graph untouched — when the drop is incompatible, so the canvas can reject
  /// it visibly.
  bool connectViaGesture(PatchPortId source, PatchPortId target) {
    if (!canConnect(source, target)) return false;
    final cable = _cableFor(source, target);
    if (cable == null) return false;
    undoScope.run(ConnectCableCommand(this, cable));
    return true;
  }

  /// Delete the current selection: the selected cable, or the selected nodes
  /// with their cables. A no-op when nothing is selected.
  void deleteSelection() {
    final cable = graph.selectedCable;
    if (cable != null) {
      undoScope.run(DeleteCableCommand(this, cable));
      return;
    }
    final ids = graph.selectedNodes;
    if (ids.isEmpty) return;
    undoScope.run(DeletePatchNodesCommand(this, ids));
  }

  /// Duplicate the selected nodes (and their intra-selection cables) one grid
  /// step down-right; the copies become the selection. A no-op with no nodes
  /// selected.
  void duplicateSelection() {
    final ids = graph.selectedNodes;
    if (ids.isEmpty) return;
    const step = PatchCanvasConstants.gridCell;
    undoScope.run(
      DuplicatePatchSelectionCommand(
        this,
        sourceIds: ids,
        offset: const Offset(step, step),
      ),
    );
  }

  /// Apply a new creation-argument string to a node from the params dialog
  /// (design §7), journaled as one [SetPatchParamsCommand] so Ctrl+Z restores
  /// the prior parameters. A no-op when the args are unchanged, so re-opening
  /// the dialog and pressing done without an edit records nothing.
  void applyParams(PatchNodeId id, String args) {
    if (argsOf(id) == args) return;
    undoScope.run(SetPatchParamsCommand(this, id, args));
  }

  void undo() => undoScope.undo();

  void redo() => undoScope.redo();

  // ─── primitives (called by the gesture commands) ─────────────────────

  /// Place [id] at [position] and persist to the native GUI properties.
  void placeNode(PatchNodeId id, Offset position) {
    final n = graph.nodeById(id);
    if (n == null) return;
    n.moveTo(position);
    final native = _nativeByNode[id];
    if (native != null) _gateway.setNodePosition(instanceId, native, position);
  }

  /// Reconfigure the object at [id] with a new creation-argument string,
  /// persisting it to the native object via `setParams`. Primitive called by
  /// [SetPatchParamsCommand]; author through [applyParams] so the change is
  /// undoable.
  void setNodeParams(PatchNodeId id, String args) {
    final native = _nativeByNode[id];
    if (native == null) return;
    _gateway.setParams(instanceId, native, args);
    _argsByNode[id] = args;
  }

  /// Wire [cable] into the native patcher and the Dart mirror.
  void addCablePrimitive(PatchCable cable) {
    final src = _nativeByNode[cable.source.nodeId];
    final dst = _nativeByNode[cable.target.nodeId];
    if (src != null && dst != null) {
      _gateway.connect(
        instanceId,
        fromHandleId: src,
        outlet: cable.source.index,
        toHandleId: dst,
        inlet: cable.target.index,
      );
    }
    graph.addCable(cable);
  }

  /// Drop [cable] from the native patcher and the Dart mirror.
  void removeCablePrimitive(PatchCable cable) {
    final src = _nativeByNode[cable.source.nodeId];
    final dst = _nativeByNode[cable.target.nodeId];
    if (src != null && dst != null) {
      _gateway.disconnect(
        instanceId,
        fromHandleId: src,
        outlet: cable.source.index,
        toHandleId: dst,
        inlet: cable.target.index,
      );
    }
    graph.removeCable(cable);
  }

  /// The full spec of the node at [id] — everything a restore/duplicate needs.
  PatchNodeSpec captureSpec(PatchNodeId id) {
    final n = graph.nodeById(id)!;
    return PatchNodeSpec(
      type: n.type,
      args: _argsByNode[id] ?? '',
      title: n.title,
      voice: n.voice,
      position: n.position,
      size: n.size,
      inputs: n.inputs,
      outputs: n.outputs,
    );
  }

  /// Cables with *either* endpoint among [ids].
  List<PatchCable> cablesTouching(Set<PatchNodeId> ids) => graph.cables
      .where(
        (c) => ids.contains(c.source.nodeId) || ids.contains(c.target.nodeId),
      )
      .toList();

  /// Cables with *both* endpoints among [ids] — what a duplicate carries over.
  List<PatchCable> cablesWithin(Set<PatchNodeId> ids) => graph.cables
      .where(
        (c) => ids.contains(c.source.nodeId) && ids.contains(c.target.nodeId),
      )
      .toList();

  /// Delete the object at [id] from the native patcher and the graph, forgetting
  /// its id mapping. Any touching cables must already be gone.
  void deleteNodePrimitive(PatchNodeId id) {
    final native = _nativeByNode[id];
    if (native != null) _gateway.deleteObject(instanceId, native);
    graph.removeNode(id);
    _nativeByNode.remove(id);
    _argsByNode.remove(id);
  }

  /// Recreate a previously-deleted node under its **same** logical [id] from
  /// [spec] — a fresh native object bound to the old id, so cables and lower
  /// undo commands stay valid.
  void restoreNodePrimitive(PatchNodeId id, PatchNodeSpec spec) {
    final native = _gateway.createObject(
      instanceId,
      spec.type,
      args: spec.args,
    );
    _nativeByNode[id] = native;
    _argsByNode[id] = spec.args;
    _gateway.setNodePosition(instanceId, native, spec.position);
    graph.addNode(_nodeFromSpec(id, spec));
  }

  /// Create a *new* node from [spec] under a fresh logical id — the duplicate
  /// path. Returns the minted id.
  PatchNodeId createNodePrimitive(PatchNodeSpec spec) {
    final native = _gateway.createObject(
      instanceId,
      spec.type,
      args: spec.args,
    );
    final id = _mintLogicalId(native);
    _nativeByNode[id] = native;
    _argsByNode[id] = spec.args;
    _gateway.setNodePosition(instanceId, native, spec.position);
    graph.addNode(_nodeFromSpec(id, spec));
    return id;
  }

  PatchNode _nodeFromSpec(PatchNodeId id, PatchNodeSpec spec) => PatchNode(
    id: id,
    type: spec.type,
    title: spec.title,
    voice: spec.voice,
    position: spec.position,
    size: spec.size,
    inputs: spec.inputs,
    outputs: spec.outputs,
  );

  // ─── audio source placement ──────────────────────────────────────────

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
    if (_ownsInstance) _gateway.disposeInstance(instanceId);
    undoScope.dispose();
    transform.dispose();
    graph.dispose();
  }
}
