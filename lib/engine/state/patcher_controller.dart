import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../design/widgets/patcher/patch_canvas_constants.dart';
import '../../design/widgets/patcher/patch_note_box.dart';
import '../../design/widgets/patcher/patch_object_box_metrics.dart';
import '../../domain/patcher/patch_cable.dart';
import '../../domain/patcher/patch_graph.dart';
import '../../domain/patcher/patch_node.dart';
import '../../domain/patcher/patch_node_id.dart';
import '../../domain/patcher/patch_port.dart';
import '../../domain/patcher/patch_port_id.dart';
import '../../domain/patcher/patch_port_kind.dart';
import '../../domain/patcher/patch_type_name.dart';
import '../../domain/project/undo_scope.dart';
import '../bridge/patch_object_descriptor.dart';
import '../bridge/patch_pin_compatibility.dart';
import '../bridge/patcher_gateway.dart';
import '../bridge/patcher_node_snapshot.dart';
import 'node_type_registry.dart';
import 'patch_clipboard.dart';
import 'patch_clipboard_cable.dart';
import 'patch_clipboard_data.dart';
import 'patch_node_spec.dart';
import 'patcher_commands/connect_cable_command.dart';
import 'patcher_commands/create_patch_object_command.dart';
import 'patcher_commands/delete_cable_command.dart';
import 'patcher_commands/delete_patch_nodes_command.dart';
import 'patcher_commands/duplicate_patch_selection_command.dart';
import 'patcher_commands/move_patch_nodes_command.dart';
import 'patcher_commands/paste_patch_clipboard_command.dart';
import 'patcher_commands/reroute_cable_command.dart';
import 'patcher_commands/retype_patch_object_command.dart';
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
  PatcherController(
    this._gateway, {
    int mainOutputs = 2,
    String name = '',
    PatchClipboard? clipboard,
  }) : instanceId = _gateway.createInstance(
         mainOutputs: mainOutputs,
         name: name,
       ),
       clipboard = clipboard ?? PatchClipboard(),
       _ownsInstance = true;

  /// Bind an editor to an already-created gateway [instanceId] (the reconciler's
  /// per-entity patcher). The controller drives edits on it but does **not** own
  /// it: [dispose] frees only the Dart-side resources, leaving the native patcher
  /// to whoever minted the instance.
  PatcherController.bound(
    this._gateway, {
    required this.instanceId,
    PatchClipboard? clipboard,
  }) : clipboard = clipboard ?? PatchClipboard(),
       _ownsInstance = false;

  final PatcherGateway _gateway;

  /// The copy buffer `Ctrl+C` fills and `Ctrl+V` pastes from (issue #435).
  /// Injected by whoever minted this editor — [PatchLibraryController] hands
  /// every bound editor the *same* instance, so a fragment copied in one patch
  /// pastes into another; a standalone controller defaults to its own.
  final PatchClipboard clipboard;

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

  /// Logical node id → the `guiValue` [refreshGuiValues] last read for it, so
  /// the poll wakes a node only when the engine reports something *new*. A node
  /// absent from the map counts as the empty display a fresh object has, so a
  /// value that arrived before the first poll still registers as a change.
  final Map<PatchNodeId, String> _guiValueByNode = {};

  /// Falls below zero to mint collision-free logical ids when a native handle
  /// value is already in use (only possible if the native side reuses handles).
  int _syntheticFloor = -1;

  /// Origin positions captured at the start of a body drag, so the release can
  /// journal one move command for the whole gesture.
  final Map<PatchNodeId, Offset> _dragStart = {};

  /// The node a move is measured from — the one under the press for a body
  /// drag, the first of the selection for a keyboard nudge. Grid snapping
  /// (issue #368) quantises *this* node and shifts the rest by the same offset,
  /// so a snapped selection keeps its internal arrangement instead of
  /// collapsing every node onto its own nearest cell.
  PatchNodeId? _dragAnchor;

  /// The cable a re-route gesture detached, held while its free end follows the
  /// pointer (issue #359). Null whenever no re-route is in flight.
  PatchCable? _reroutingCable;

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

  /// Create a node straight from a catalogue [desc] at [position].
  ///
  /// Unlike [addNode] (which takes a hand-authored [NodeDescriptor] for the
  /// seeded demo bodies), this creates *any* engine object from its palette
  /// metadata: it seeds the native object with [args] — the descriptor's
  /// documented defaults when none are given — and sizes the node to fit,
  /// which for a plain engine object means the box its own line of text needs
  /// (issue #379) and for a hand-authored GUI body its tuned size.
  ///
  /// Direct (non-undoable): the **primitive** both authoring gestures create
  /// through. Author through [createObject] so the creation lands on the undo
  /// stack like every other canvas verb.
  PatchNode addObject({
    required PatchObjectDescriptor desc,
    required Offset position,
    String? args,
    int voice = 1,
  }) {
    return _create(
      type: desc.type,
      args: args ?? _defaultArgsFor(desc),
      voice: voice,
      position: position,
      // No size: _create measures the object box, or takes the tuned size a
      // registered GUI body declares.
    );
  }

  /// Create a catalogue object at [position] as one journaled step — the
  /// authoring gesture behind both the palette **drag-to-create** (design §5)
  /// and the inline object box's Enter (issue #358). Returns the new node's
  /// logical id.
  ///
  /// [args] is the creation-argument string to mint the object with, already
  /// checked against the type's documented parameters (`PatchCreationArgs`);
  /// null falls back to those documented defaults, which is what a palette drop
  /// wants. The new node becomes the selection.
  PatchNodeId? createObject({
    required PatchObjectDescriptor desc,
    required Offset position,
    String? args,
    int voice = 1,
  }) {
    final command = CreatePatchObjectCommand(
      this,
      desc: desc,
      args: args ?? _defaultArgsFor(desc),
      position: position,
      voice: voice,
    );
    undoScope.run(command);
    return command.createdId;
  }

  /// Shared node creation: mint the native object, key it to a fresh logical
  /// id, persist its position, reify its ports, and add it to the graph.
  PatchNode _create({
    required String type,
    required String args,
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
      voice: voice,
      position: position,
      size: _sizeFor(
        type: type,
        args: args,
        inputs: snapshot.inputs,
        outputs: snapshot.outputs,
        declared: size,
      ),
      inputs: _portsFrom(snapshot, PatchPortSide.input, voice),
      outputs: _portsFrom(snapshot, PatchPortSide.output, voice),
    );
    graph.addNode(node);
    return node;
  }

  /// Reify one side of a gateway [snapshot] into [PatchPort]s for a node of
  /// [voice]. The single place a snapshot becomes ports, so node creation,
  /// mirror rebuild and the post-`setParams` re-inspect can never disagree
  /// about what the engine just reported. An absent kind (a snapshot whose
  /// kinds list is shorter than its count) falls back to `control` rather than
  /// throwing — the mirror degrades, it does not crash.
  static List<PatchPort> _portsFrom(
    PatcherNodeSnapshot snapshot,
    PatchPortSide side,
    int voice,
  ) {
    final isInput = side == PatchPortSide.input;
    final count = isInput ? snapshot.inputs : snapshot.outputs;
    final kinds = isInput ? snapshot.inputKinds : snapshot.outputKinds;
    return [
      for (var i = 0; i < count; i++)
        PatchPort(
          index: i,
          side: side,
          kind: i < kinds.length ? kinds[i] : PatchPortKind.control,
          voice: voice,
        ),
    ];
  }

  /// The documented creation-argument string for [desc] — its params' default
  /// values, space-joined. An object with no documented params (e.g. `.slider`,
  /// which registers none and crashes if handed any) yields an empty string.
  String _defaultArgsFor(PatchObjectDescriptor desc) => [
    for (final p in desc.params)
      if (p.defaultValue.isNotEmpty) p.defaultValue,
  ].join(' ');

  /// The line an **object box** prints: the object's name followed by its
  /// creation arguments, the way a Max object box reads — `sine 440`,
  /// `metro 250` (issue #356). Empty for a node the graph does not hold.
  ///
  /// The name is **bare**: the `~`/`.` prefix is not drawn, the box's colour
  /// says it instead (issue #380, design §12.4). The prefixed id stays the
  /// canonical one on the node itself, so nothing about typing, completing,
  /// saving or talking to the gateway changes — only what is read on screen.
  String objectLineOf(PatchNodeId id) {
    final node = graph.nodeById(id);
    if (node == null) return '';
    return objectLine(node.type, argsOf(id));
  }

  /// [objectLineOf]'s pure form, for the moment before the node exists — node
  /// creation measures its own box from this. Takes the **canonical** type and
  /// bares it, so the measurement and the render can never disagree about how
  /// many characters the line has.
  static String objectLine(String type, String args) {
    final name = PatchTypeName.bare(type);
    final trimmed = args.trim();
    return trimmed.isEmpty ? name : '$name $trimmed';
  }

  /// The line a node of [type] actually **renders** — which is what its box
  /// is measured from.
  ///
  /// For every ordinary object that is [objectLine] (`sine 440`). The note
  /// (issue #436) renders its content *alone* — a comment reading
  /// `text warm pad` would defeat the point of looking like a note — so it is
  /// measured from [PatchNoteBox.displayText] instead. [objectLine] stays what
  /// the inline box opens holding for **every** type, note included: there the
  /// name is how the line re-resolves its object.
  static String displayLine(String type, String args) =>
      PatchTypeName.isNote(type)
      ? PatchNoteBox.displayText(args)
      : objectLine(type, args);

  /// Whether a node of [type] renders as an object box rather than as a bare
  /// GUI control (design §7). An **unregistered** type is one too: a plain
  /// engine object dragged off the palette has no hand-authored body and never
  /// will.
  ///
  /// Public because the canvas asks the same question the sizing does: an
  /// object box is the thing a double-click edits in place (issue #382), and a
  /// GUI object is operated through its body instead. Two answers would be one
  /// too many.
  static bool isObjectBox(String type) =>
      NodeTypeRegistry.instance.find(type)?.isObjectBox ?? true;

  /// The box a node of [type] needs (issue #379).
  ///
  /// An **object box** is measured from the line it prints
  /// ([PatchObjectBoxMetrics]): as wide as its text, floored by the minimum
  /// width its port count demands and capped past which the line ellipsises,
  /// and one text line plus padding tall. Ports spread along the top and bottom
  /// edges at fixed spacing since issue #377, so the count sets a *width* floor
  /// a line of text absorbs rather than the height floor it used to force —
  /// under which no one-line box was possible at all.
  ///
  /// A **GUI object** keeps the tuned `defaultSize` its descriptor declares —
  /// the rectangle its bare control fills edge to edge since issue #381 — but is
  /// held to the same port floor, since its ports hang off the very same top and
  /// bottom edges and a control narrower than its dots would strand them.
  ///
  /// [declared] lets a caller name the size instead of the registry, which is
  /// what `addNode` does for a descriptor that was never registered; it goes
  /// through the same floor rather than around it.
  Size _sizeFor({
    required String type,
    required String args,
    required int inputs,
    required int outputs,
    Size? declared,
  }) {
    final tuned = declared ?? NodeTypeRegistry.instance.find(type)?.defaultSize;
    if (tuned != null) {
      final floor = PatchCanvasConstants.minWidthForPorts(
        math.max(inputs, outputs),
      );
      return Size(math.max(tuned.width, floor), tuned.height);
    }
    return PatchObjectBoxMetrics.sizeFor(
      // The *display* line: a note is measured from its content alone
      // (issue #436), every other box from `name args`.
      text: displayLine(type, args),
      inputs: inputs,
      outputs: outputs,
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
    _guiValueByNode.clear();

    final snapshot = _gateway.enumerate(instanceId);
    for (final obj in snapshot.objects) {
      final id = PatchNodeId(obj.handleId);
      _nativeByNode[id] = obj.handleId;
      _argsByNode[id] = obj.args;
      final ports = obj.ports;
      graph.addNode(
        PatchNode(
          id: id,
          type: obj.type,
          voice: 1,
          position: obj.position ?? Offset.zero,
          size: _sizeFor(
            type: obj.type,
            args: obj.args,
            inputs: ports.inputs,
            outputs: ports.outputs,
          ),
          inputs: _portsFrom(ports, PatchPortSide.input, 1),
          outputs: _portsFrom(ports, PatchPortSide.output, 1),
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

  // ─── live display refresh (issue #357) ───────────────────────────────

  /// Whether this patch holds any node whose body renders the engine's
  /// `guiValue` ([NodeDescriptor.readsGuiValue]) — the gate the surface's
  /// refresh runs on, so a patch of plain objects schedules no polling at all.
  bool get hasGuiValueNodes => graph.nodes.any(_readsGuiValue);

  /// Re-read the engine's display value for every node whose body renders one
  /// and wake the ones whose value **changed**. Returns how many were woken.
  ///
  /// The Dart side never hears about a value that arrives over a *cable*: the
  /// native object updates and nothing on the canvas knows, so a body that only
  /// re-read after its own push showed a stale number the moment the graph did
  /// anything by itself (issue #357). This closes that loop by asking — driven
  /// by the surface's `PatchGuiPoller` while the patcher is on screen, and by
  /// nothing at all while it is not.
  ///
  /// Two economies keep an idle patch free: only [_readsGuiValue] nodes are
  /// read, and only a value different from the last one seen raises
  /// [PatchNode.markGuiValueChanged]. A patch nobody is driving therefore
  /// repaints nothing, however long the poll runs.
  ///
  /// If the gateway ever grows a cheaper change signal (a per-object dirty flag
  /// from `dart-yse`), it swaps in behind this one method — the surface, the
  /// nodes and the bodies stay as they are.
  int refreshGuiValues() {
    var woken = 0;
    for (final node in graph.nodes) {
      if (!_readsGuiValue(node)) continue;
      final value = guiValueOf(node.id);
      final previous = _guiValueByNode[node.id] ?? '';
      _guiValueByNode[node.id] = value;
      if (previous == value) continue;
      node.markGuiValueChanged();
      woken++;
    }
    return woken;
  }

  /// Whether [node]'s registered body displays a `guiValue`. An object box
  /// prints its creation arguments instead — which only a journaled
  /// `setParams` changes — so it is never polled.
  static bool _readsGuiValue(PatchNode node) =>
      NodeTypeRegistry.instance.find(node.type)?.readsGuiValue ?? false;

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
    beginSelectionMove(anchor: primary);
  }

  /// Capture the current selection's origins so [dragSelectedBy] can preview a
  /// move and [endNodeDrag] can journal it as one step.
  ///
  /// The pointer enters through [beginNodeDrag], which adds the "the node under
  /// the press joins the selection" rule on top; the **keyboard nudge** (issue
  /// #368) enters here, because an arrow key has no node under it — it moves
  /// whatever is already selected, and calling this repeatedly during one
  /// keypress burst would throw away the origins the burst is measured from, so
  /// the canvas calls it once per burst.
  ///
  /// A no-op with nothing selected: a move of no nodes has no origins to keep,
  /// and leaving [_dragStart] empty is exactly what makes [endNodeDrag] journal
  /// nothing.
  void beginSelectionMove({PatchNodeId? anchor}) {
    final ids = graph.selectedNodes;
    _dragAnchor = anchor ?? (ids.isEmpty ? null : ids.first);
    _dragStart
      ..clear()
      ..addEntries(
        ids.map(
          (id) => MapEntry(id, graph.nodeById(id)?.position ?? Offset.zero),
        ),
      );
  }

  /// Whether a move (drag or nudge) is currently in flight — the canvas reads
  /// it to tell a nudge burst that is still open from one already committed.
  bool get isMovingNodes => _dragStart.isNotEmpty;

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
    _dragAnchor = null;
  }

  /// Commit the body drag: journal one move for the whole selection (nothing
  /// when the net movement is zero).
  ///
  /// With [snapToGrid] the drop quantises to the canvas's minor grid (issue
  /// #368) — the anchor node lands on the nearest
  /// [PatchCanvasConstants.gridCell] and everything dragged with it shifts by
  /// that same offset. Snapping happens **here** rather than during the drag so
  /// the node stays glued to the pointer while it is moving, and only the drop
  /// is disciplined; and it lands in the journaled destination, so undo and
  /// redo walk the snapped positions instead of re-snapping on replay.
  void endNodeDrag({bool snapToGrid = false}) {
    if (_dragStart.isEmpty) return;
    final adjust = snapToGrid ? _snapAdjustment() : Offset.zero;
    final from = <PatchNodeId, Offset>{};
    final to = <PatchNodeId, Offset>{};
    var moved = false;
    _dragStart.forEach((id, start) {
      final n = graph.nodeById(id);
      if (n == null) return;
      final end = n.position + adjust;
      from[id] = start;
      to[id] = end;
      if (end != start) moved = true;
    });
    _dragStart.clear();
    _dragAnchor = null;
    if (!moved) {
      // Nothing to journal — but a snap that cancelled the gesture out (a short
      // drag off an on-grid node, quantised straight back) still has to put the
      // live nodes on the position the drop decided, not on the one the preview
      // last drew them at.
      if (adjust != Offset.zero) from.forEach(placeNode);
      return;
    }
    undoScope.run(MovePatchNodesCommand(this, from: from, to: to));
  }

  /// How far the whole moved set has to shift for the anchor node to sit on the
  /// grid. Zero when the anchor is gone (deleted mid-gesture) — a move that
  /// cannot be measured is better left where the pointer put it.
  Offset _snapAdjustment() {
    final id = _dragAnchor ?? _dragStart.keys.first;
    final anchor = graph.nodeById(id);
    if (anchor == null) return Offset.zero;
    return _snap(anchor.position) - anchor.position;
  }

  /// The nearest minor-grid point to [p] — the same 16px lattice the grid
  /// backdrop paints and the state-machine canvas snaps to.
  static Offset _snap(Offset p) {
    const step = PatchCanvasConstants.gridCell;
    return Offset(
      (p.dx / step).roundToDouble() * step,
      (p.dy / step).roundToDouble() * step,
    );
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

  // ─── cable re-routing (issue #359) ───────────────────────────────────

  /// The cable currently detached by a re-route gesture, or null. The canvas
  /// reads it to tell a *re-route* release apart from a plain connect.
  PatchCable? get reroutingCable => _reroutingCable;

  /// Detach [cable] and start dragging the end that is **not** [anchor], so the
  /// free end follows the pointer while [anchor] stays put.
  ///
  /// Unjournaled on purpose: a detach is only half a gesture. The release
  /// decides what actually happened — [rerouteViaGesture] for a drop on a port,
  /// [dropReroutedCable] for a drop on nothing, [abortCableReroute] for a
  /// gesture that never finished — and journals *that*, once.
  void beginCableReroute(PatchCable cable, {required PatchPortId anchor}) {
    abortCableReroute();
    _reroutingCable = cable;
    removeCablePrimitive(cable);
    graph.beginCableDrag(anchor);
  }

  /// Put a detached cable back exactly as it was and forget the gesture.
  ///
  /// The cancel path ([PatcherCanvas]'s `_resetGesture`): a pointer torn away
  /// mid-re-route never delivers its release, and a cable that quietly vanished
  /// because the window lost capture is the worst possible outcome. Safe to
  /// call with no re-route in flight.
  void abortCableReroute() {
    final cable = _reroutingCable;
    _reroutingCable = null;
    if (cable != null) addCablePrimitive(cable);
  }

  /// Commit a re-route onto [source] → [target] as one journaled step. Returns
  /// false — leaving the cable where it was — when the drop is incompatible, so
  /// the canvas can reject it visibly.
  ///
  /// The detached cable is restored *first*, so the command runs against the
  /// graph the gesture started from: `apply`/`revert` then describe the whole
  /// re-route on their own, and an undo of anything below it sees a consistent
  /// patch rather than one mid-gesture.
  bool rerouteViaGesture(PatchPortId source, PatchPortId target) {
    final old = _reroutingCable;
    _reroutingCable = null;
    if (old == null) return false;
    addCablePrimitive(old);
    // Dropped back on the port it came from: nothing changed, so nothing is
    // journaled — and the duplicate check below would otherwise call the
    // cable's own home incompatible.
    if (source == old.source && target == old.target) return true;
    if (!canConnect(source, target)) return false;
    final next = _cableFor(source, target);
    if (next == null) return false;
    undoScope.run(RerouteCableCommand(this, from: old, to: next));
    return true;
  }

  /// Drop a detached cable for good — the drag was released over empty canvas.
  /// Journaled as a plain delete, so `Ctrl+Z` re-wires it.
  void dropReroutedCable() {
    final cable = _reroutingCable;
    _reroutingCable = null;
    if (cable == null) return;
    addCablePrimitive(cable);
    undoScope.run(DeleteCableCommand(this, cable));
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

  /// Copy the selected nodes — and every cable with *both* endpoints in the
  /// selection — into the [clipboard] (`Ctrl+C`, issue #435).
  ///
  /// Captures full [PatchNodeSpec]s and index-keyed cables, so the copy is
  /// self-contained: it pastes after the originals are deleted, and into a
  /// different patch when the clipboard is shared. Copying is not an edit —
  /// nothing is journaled — and an empty selection is a no-op that leaves the
  /// previous copy intact.
  void copySelection() {
    final order = graph.selectedNodes.toList();
    if (order.isEmpty) return;
    final index = {for (var i = 0; i < order.length; i++) order[i]: i};
    clipboard.set(
      PatchClipboardData(
        nodes: [for (final id in order) captureSpec(id)],
        cables: [
          for (final c in cablesWithin(index.keys.toSet()))
            PatchClipboardCable(
              sourceNode: index[c.source.nodeId]!,
              sourceOutlet: c.source.index,
              targetNode: index[c.target.nodeId]!,
              targetInlet: c.target.index,
              kind: c.kind,
            ),
        ],
      ),
    );
  }

  /// Paste the clipboard's fragment as one journaled step (`Ctrl+V`, issue
  /// #435); the pasted set becomes the selection, ready to drag. Each repeated
  /// paste of the same copy lands one grid step further down-right — the
  /// duplicate offset, per generation — so copies never stack on the same
  /// spot. A no-op while the clipboard is empty.
  void pasteClipboard() {
    final data = clipboard.data;
    if (data == null || data.isEmpty) return;
    final step = PatchCanvasConstants.gridCell * clipboard.takePasteStep();
    undoScope.run(
      PastePatchClipboardCommand(this, data: data, offset: Offset(step, step)),
    );
  }

  /// Apply a new creation-argument string to a node — typed into its object box
  /// on the canvas (design §7, issue #382) — journaled as one
  /// [SetPatchParamsCommand] so Ctrl+Z restores the prior parameters. A no-op
  /// when the args are unchanged, so opening the box and pressing Enter without
  /// an edit records nothing.
  void applyParams(PatchNodeId id, String args) {
    if (argsOf(id) == args) return;
    undoScope.run(SetPatchParamsCommand(this, id, args));
  }

  /// Commit what was typed into an object box — the one entry point Enter comes
  /// through, whichever of the two edits it turns out to be (design §7).
  ///
  /// The box hands back a resolved catalogue entry and a checked argument
  /// string, and the *type* decides which edit this is:
  /// - **Same type** — new arguments for the object that is there: one journaled
  ///   [applyParams], unchanged since issue #382, and a no-op when the arguments
  ///   did not move either.
  /// - **A different type** (issue #383) — typing `saw 300` over a `sine 300`.
  ///   The engine cannot turn one object into another, so the native object is
  ///   replaced; the node keeps its id, its position and its selection, and
  ///   carries over every cable the new object still has room for
  ///   ([retypeNodePrimitive]). One journaled step, so a single `Ctrl+Z` puts
  ///   the old object *and* every dropped cable back.
  ///
  /// Returns how many connections the retype could not carry — zero for an
  /// argument edit, and what the canvas says out loud when it is not, since a
  /// retype that silently drops two cables is discovered an hour later.
  int applyBoxEdit(
    PatchNodeId id, {
    required PatchObjectDescriptor desc,
    required String args,
  }) {
    final node = graph.nodeById(id);
    if (node == null) return 0;
    if (node.type == desc.type) {
      applyParams(id, args);
      return 0;
    }
    final command = RetypePatchObjectCommand(
      this,
      id: id,
      desc: desc,
      args: args,
    );
    undoScope.run(command);
    return command.droppedCount;
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
  ///
  /// Re-inspects the object afterwards and reshapes the node when the new
  /// arguments changed its port count or the box its line needs ([_resyncShape],
  /// issues #356/#379), then wakes it ([PatchNode.markParamsChanged]) so the
  /// object box repaints with the arguments it now carries. Both the apply and
  /// its undo/redo come through here, so all three follow (issue #354).
  ///
  /// Returns the cables that had to be dropped because the reconfigured object
  /// no longer has the port they hung off; [SetPatchParamsCommand] re-wires them
  /// on undo, so a param edit that cost a connection is undone whole.
  List<PatchCable> setNodeParams(PatchNodeId id, String args) {
    final native = _nativeByNode[id];
    if (native == null) return const [];
    _gateway.setParams(instanceId, native, args);
    _argsByNode[id] = args;
    final dropped = _resyncShape(id, native);
    graph.nodeById(id)?.markParamsChanged();
    return dropped;
  }

  /// Re-read [id]'s port topology from the native object and reshape the node
  /// when its ports — or the box its line of text now needs — no longer match
  /// the mirror (issues #356, #379).
  ///
  /// An object's inlet/outlet count follows its creation arguments, so a
  /// `setParams` can reshape the very object the canvas is drawing. Without
  /// this the mirror goes stale the moment the arguments are applied: port
  /// dots drawn where the object has none, cables wired to outlets that no
  /// longer exist, drag-time compatibility answered against a shape the engine
  /// forgot.
  ///
  /// The **box** is re-measured on the same pass, because an object box is as
  /// wide as its text: retyping `.metro 250` as `.metro 60000` makes a longer
  /// line, and a box left at its old width would ellipsise the very edit that
  /// was just made.
  ///
  /// Cables hanging off a port the object lost are dropped from the native
  /// patcher *and* the mirror, and returned so the caller can restore them.
  /// Returns an empty list whenever nothing was disconnected — the common case,
  /// and the only one for the objects whose arity is fixed.
  List<PatchCable> _resyncShape(PatchNodeId id, int native) {
    final node = graph.nodeById(id);
    if (node == null) return const [];
    final snapshot = _gateway.inspect(instanceId, native);
    final inputs = _portsFrom(snapshot, PatchPortSide.input, node.voice);
    final outputs = _portsFrom(snapshot, PatchPortSide.output, node.voice);
    final size = _sizeSeating(node, inputs.length, outputs.length);
    final samePorts =
        _samePorts(node.inputs, inputs) && _samePorts(node.outputs, outputs);
    if (samePorts && size == node.size) return const [];
    // Empty whenever the counts held: the filter only catches an index the
    // object no longer has.
    final dropped = graph.cables
        .where(
          (c) =>
              (c.target.nodeId == id && c.target.index >= inputs.length) ||
              (c.source.nodeId == id && c.source.index >= outputs.length),
        )
        .toList();
    for (final cable in dropped) {
      removeCablePrimitive(cable);
    }
    node.reshapePorts(inputs: inputs, outputs: outputs, size: size);
    return dropped;
  }

  /// Whether two port lists describe the same topology — same count, same
  /// audio/control kinds in the same order. Index/side/voice are derived from
  /// the position, so they add nothing to compare.
  static bool _samePorts(List<PatchPort> a, List<PatchPort> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].kind != b[i].kind) return false;
    }
    return true;
  }

  /// The box [node] should hold after a reconfiguration.
  ///
  /// An **object box** is re-measured outright from the line it now prints and
  /// the ports it now has (issue #379) — it is intrinsically sized, so shrinking
  /// back is as correct as growing. A **GUI object** keeps its tuned size and
  /// only ever grows, and only in **width**, when a new port count needs more
  /// than the current box seats — the axis ports spread along since #377 — so a
  /// hand-authored body never jumps around as ports come and go.
  Size _sizeSeating(PatchNode node, int inputs, int outputs) {
    if (isObjectBox(node.type)) {
      return PatchObjectBoxMetrics.sizeFor(
        text: displayLine(node.type, argsOf(node.id)),
        inputs: inputs,
        outputs: outputs,
      );
    }
    final needed = PatchCanvasConstants.minWidthForPorts(
      math.max(inputs, outputs),
    );
    return node.size.width >= needed
        ? node.size
        : Size(needed, node.size.height);
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
    _guiValueByNode.remove(id);
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

  /// Replace the object at [id] with a fresh one of [type]/[args], under the
  /// **same** logical id and at the same position — the retype primitive
  /// (issue #383). Author through [applyBoxEdit] so the change is undoable.
  ///
  /// The engine has no verb that turns one object into another, so this deletes
  /// the native object and mints the new one. Everything the canvas knows the
  /// node by is deliberately kept: the logical id (so cables and lower undo
  /// commands that named it stay valid), the position, the voice, and — because
  /// the node is *replaced* in the graph rather than removed and re-added — the
  /// selection ring it was carrying.
  ///
  /// **Cables are carried over where they still land.** Every cable touching the
  /// node is unwired first (the native object is about to go), then re-wired one
  /// by one against the new topology through the very same [canConnect] the
  /// authoring gesture asks: the port index has to still exist on the same side
  /// and the types still have to accept each other. The ones that do not are
  /// returned rather than silently forgotten, so the command can wire them back
  /// on undo and the canvas can say how many were lost.
  List<PatchCable> retypeNodePrimitive(
    PatchNodeId id, {
    required String type,
    required String args,
  }) {
    final node = graph.nodeById(id);
    if (node == null) return const [];
    final touching = cablesTouching({id});
    for (final cable in touching) {
      removeCablePrimitive(cable);
    }
    final previous = _nativeByNode[id];
    if (previous != null) _gateway.deleteObject(instanceId, previous);
    final native = _gateway.createObject(instanceId, type, args: args);
    _nativeByNode[id] = native;
    _argsByNode[id] = args;
    // The new object has a display value of its own (or none at all); the one
    // the poll last read belonged to the object that just went.
    _guiValueByNode.remove(id);
    _gateway.setNodePosition(instanceId, native, node.position);
    final snapshot = _gateway.inspect(instanceId, native);
    graph.addNode(
      PatchNode(
        id: id,
        type: type,
        voice: node.voice,
        position: node.position,
        size: _sizeFor(
          type: type,
          args: args,
          inputs: snapshot.inputs,
          outputs: snapshot.outputs,
        ),
        inputs: _portsFrom(snapshot, PatchPortSide.input, node.voice),
        outputs: _portsFrom(snapshot, PatchPortSide.output, node.voice),
      ),
    );
    final dropped = <PatchCable>[];
    for (final cable in touching) {
      // Rebuilt rather than re-added: the cable's kind is its *source outlet's*
      // kind, and a retype of that end may well have changed it.
      final carried = canConnect(cable.source, cable.target)
          ? _cableFor(cable.source, cable.target)
          : null;
      if (carried == null) {
        dropped.add(cable);
        continue;
      }
      addCablePrimitive(carried);
    }
    return dropped;
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
