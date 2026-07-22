import 'dart:convert';
import 'dart:ui';

import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/bridge/patcher_gateway.dart';
import 'package:phi/engine/bridge/patcher_graph_snapshot.dart';
import 'package:phi/engine/bridge/patcher_node_snapshot.dart';
import 'package:yse/yse.dart';

/// In-memory [PatcherGateway] used in unit and widget tests.
///
/// Models the full multi-instance lifecycle: one [FakeInstance] per id
/// [createInstance] hands out, each with its own objects / cables / mounted
/// state / named receivers, so a test can assert that ops on one instance
/// never leak to another. [calls] is a flat, ordered global log of every
/// call for sequence assertions; object handle ids are globally unique so a
/// call string identifies its object without an instance prefix.
class FakePatcherGateway implements PatcherGateway {
  final List<String> calls = [];

  final Map<int, FakeInstance> instances = {};
  int _nextInstanceId = 1;
  int _nextObjectId = 1;

  /// Override the default port topology for a given object type. Tests can
  /// stub e.g. an exotic node with custom inlet/outlet counts.
  final Map<String, PatcherNodeSnapshot> topologyOverrides = {};

  /// Override the metadata catalogue [objectTypes] filters. When null the
  /// built-in [_defaultCatalogue] is used. The `patcher` type is always
  /// filtered out regardless (design §10 decision 2).
  List<PatchObjectDescriptor>? objectTypesCatalogue;

  // ─── convenience aggregates (single-instance tests) ──────────────────

  /// Every object across every instance — convenient when a test uses one
  /// instance. Prefer [FakeInstance.nodes] for isolation assertions.
  Map<int, FakeNode> get nodes => {
    for (final inst in instances.values) ...inst.nodes,
  };

  /// Every cable across every instance.
  List<FakeCable> get cables => [
    for (final inst in instances.values) ...inst.cables,
  ];

  /// Whether any instance is mounted.
  bool get mounted => instances.values.any((i) => i.mounted);

  FakeInstance _inst(int instanceId) => instances[instanceId]!;

  @override
  int createInstance({int mainOutputs = 2}) {
    final id = _nextInstanceId++;
    calls.add('createInstance:$id:$mainOutputs');
    instances[id] = FakeInstance(mainOutputs: mainOutputs);
    return id;
  }

  @override
  void disposeInstance(int instanceId) {
    calls.add('disposeInstance:$instanceId');
    instances.remove(instanceId);
  }

  @override
  void disposeAll() {
    calls.add('disposeAll');
    instances.clear();
  }

  @override
  int createObject(int instanceId, String type, {String args = ''}) {
    final id = _nextObjectId++;
    calls.add('createObject:$id:$type:$args');
    final inst = _inst(instanceId);
    inst.nodes[id] = FakeNode(type: type, args: args);
    // Model the named `.r` receiver so pass* can resolve it per-instance.
    if (type == Obj.gReceive && args.isNotEmpty) inst.receivers.add(args);
    return id;
  }

  @override
  void deleteObject(int instanceId, int handleId) {
    calls.add('deleteObject:$handleId');
    final inst = _inst(instanceId);
    inst.nodes.remove(handleId);
    inst.cables.removeWhere(
      (c) => c.fromHandleId == handleId || c.toHandleId == handleId,
    );
  }

  @override
  void connect(
    int instanceId, {
    required int fromHandleId,
    required int outlet,
    required int toHandleId,
    required int inlet,
  }) {
    calls.add('connect:$fromHandleId:$outlet->$toHandleId:$inlet');
    _inst(instanceId).cables.add(
      FakeCable(
        fromHandleId: fromHandleId,
        outlet: outlet,
        toHandleId: toHandleId,
        inlet: inlet,
      ),
    );
  }

  @override
  void disconnect(
    int instanceId, {
    required int fromHandleId,
    required int outlet,
    required int toHandleId,
    required int inlet,
  }) {
    calls.add('disconnect:$fromHandleId:$outlet->$toHandleId:$inlet');
    _inst(instanceId).cables.removeWhere(
      (c) =>
          c.fromHandleId == fromHandleId &&
          c.outlet == outlet &&
          c.toHandleId == toHandleId &&
          c.inlet == inlet,
    );
  }

  @override
  PatcherNodeSnapshot inspect(int instanceId, int handleId) {
    final type = _inst(instanceId).nodes[handleId]?.type ?? '';
    final override = topologyOverrides[type];
    if (override != null) return override;
    return _defaultTopologyFor(type);
  }

  @override
  PatcherGraphSnapshot enumerate(int instanceId) {
    final inst = _inst(instanceId);
    return PatcherGraphSnapshot(
      objects: [
        for (final entry in inst.nodes.entries)
          PatcherObjectSnapshot(
            handleId: entry.key,
            type: entry.value.type,
            args: entry.value.args,
            position: entry.value.position,
            ports: inspect(instanceId, entry.key),
          ),
      ],
      connections: [
        for (final c in inst.cables)
          PatcherConnectionSnapshot(
            fromHandleId: c.fromHandleId,
            outlet: c.outlet,
            toHandleId: c.toHandleId,
            inlet: c.inlet,
          ),
      ],
    );
  }

  @override
  void setNodePosition(int instanceId, int handleId, Offset position) {
    calls.add(
      'setNodePosition:$handleId:${position.dx.toStringAsFixed(1)}'
      ':${position.dy.toStringAsFixed(1)}',
    );
    _inst(instanceId).nodes[handleId]?.position = position;
  }

  @override
  Offset? getNodePosition(int instanceId, int handleId) =>
      _inst(instanceId).nodes[handleId]?.position;

  @override
  void sendFloat(int instanceId, int handleId, int inlet, double value) {
    calls.add('sendFloat:$handleId:$inlet:${value.toStringAsFixed(3)}');
    final node = _inst(instanceId).nodes[handleId];
    if (node == null) return;
    node.lastValueByInlet[inlet] = value;
    // A control object's "hot" inlet (0) drives its display value — a slider,
    // number or toggle reflects the last value set into it, exactly what the
    // native side reports back through `guiValue`.
    if (inlet == 0) node.guiValue = _formatGui(value);
  }

  @override
  void sendBang(int instanceId, int handleId, int inlet) {
    calls.add('sendBang:$handleId:$inlet');
    _inst(instanceId).nodes[handleId]?.bangedInlets.add(inlet);
  }

  @override
  String guiValue(int instanceId, int handleId) =>
      _inst(instanceId).nodes[handleId]?.guiValue ?? '';

  @override
  void setParams(int instanceId, int handleId, String args) {
    calls.add('setParams:$handleId:$args');
    _inst(instanceId).nodes[handleId]?.args = args;
  }

  /// A whole value renders without a trailing `.0` (`3` not `3.0`), matching
  /// how the engine formats an integer-valued display.
  static String _formatGui(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  @override
  bool passBang(int instanceId, String to) {
    calls.add('passBang:$instanceId:$to');
    return _inst(instanceId).receivers.contains(to);
  }

  @override
  bool passInt(int instanceId, int value, String to) {
    calls.add('passInt:$instanceId:$value:$to');
    return _inst(instanceId).receivers.contains(to);
  }

  @override
  bool passFloat(int instanceId, double value, String to) {
    calls.add('passFloat:$instanceId:${value.toStringAsFixed(3)}:$to');
    return _inst(instanceId).receivers.contains(to);
  }

  @override
  bool passString(int instanceId, String value, String to) {
    calls.add('passString:$instanceId:$value:$to');
    return _inst(instanceId).receivers.contains(to);
  }

  @override
  void mountAsSource(int instanceId, {int? busChannelId, double volume = 1.0}) {
    calls.add(
      'mountAsSource:$instanceId:$busChannelId:${volume.toStringAsFixed(3)}',
    );
    final inst = _inst(instanceId);
    inst.mounted = true;
    inst.mountedBus = busChannelId;
  }

  @override
  void unmountSource(int instanceId) {
    calls.add('unmountSource:$instanceId');
    final inst = _inst(instanceId);
    inst.mounted = false;
    inst.mountedBus = null;
  }

  /// Serialise the instance to a **structured, re-parseable** dump — objects
  /// (id · type · args · optional x/y) and cables — so a flush → reload
  /// round-trip through [parseJson] faithfully reconstructs the graph, the way
  /// the real gateway's libyse dump does. (The old summary form carried only
  /// counts, which could not be rebuilt from.)
  @override
  String dumpJson(int instanceId) {
    final inst = _inst(instanceId);
    return jsonEncode({
      'objects': [
        for (final entry in inst.nodes.entries)
          {
            'id': entry.key,
            'type': entry.value.type,
            'args': entry.value.args,
            if (entry.value.position != null) 'x': entry.value.position!.dx,
            if (entry.value.position != null) 'y': entry.value.position!.dy,
          },
      ],
      'cables': [
        for (final c in inst.cables)
          {
            'from': c.fromHandleId,
            'outlet': c.outlet,
            'to': c.toHandleId,
            'inlet': c.inlet,
          },
      ],
    });
  }

  /// Reconstruct the instance from a [dumpJson]-shaped [content]. Tolerant of
  /// opaque/summary dumps (an `objects` that is not a list): those log and leave
  /// the instance untouched, so legacy tests that pass hand-written placeholder
  /// dumps still work. The `parseJson:<length>` log line is always recorded.
  @override
  void parseJson(int instanceId, String content) {
    calls.add('parseJson:${content.length}');
    if (content.isEmpty) return;
    final decoded = jsonDecode(content);
    if (decoded is! Map) return;
    final objects = decoded['objects'];
    if (objects is! List) return; // opaque/summary dump — nothing to rebuild.
    final inst = _inst(instanceId);
    inst.nodes.clear();
    inst.cables.clear();
    inst.receivers.clear();
    for (final raw in objects) {
      if (raw is! Map) continue;
      final id = (raw['id'] as num).toInt();
      final type = raw['type'] as String? ?? '';
      final args = raw['args'] as String? ?? '';
      final node = FakeNode(type: type, args: args);
      final x = raw['x'];
      final y = raw['y'];
      if (x is num && y is num) {
        node.position = Offset(x.toDouble(), y.toDouble());
      }
      inst.nodes[id] = node;
      if (type == Obj.gReceive && args.isNotEmpty) inst.receivers.add(args);
      // Keep freshly-minted ids clear of the reconstructed ones.
      if (id >= _nextObjectId) _nextObjectId = id + 1;
    }
    final cables = decoded['cables'];
    if (cables is List) {
      for (final raw in cables) {
        if (raw is! Map) continue;
        inst.cables.add(
          FakeCable(
            fromHandleId: (raw['from'] as num).toInt(),
            outlet: (raw['outlet'] as num).toInt(),
            toHandleId: (raw['to'] as num).toInt(),
            inlet: (raw['inlet'] as num).toInt(),
          ),
        );
      }
    }
  }

  @override
  List<PatchObjectDescriptor> objectTypes() => [
    for (final d in objectTypesCatalogue ?? _defaultCatalogue)
      if (d.type != Obj.patcher) d,
  ];

  /// Default topology for the node types the surface seeds — keeps tests
  /// realistic without stubbing on every call.
  PatcherNodeSnapshot _defaultTopologyFor(String type) {
    switch (type) {
      case Obj.dSine:
        return const PatcherNodeSnapshot(
          inputs: 1,
          outputs: 1,
          inputKinds: [PatchPortKind.control],
          outputKinds: [PatchPortKind.audio],
        );
      case Obj.dDac:
        return const PatcherNodeSnapshot(
          inputs: 2,
          outputs: 0,
          inputKinds: [PatchPortKind.audio, PatchPortKind.audio],
          outputKinds: [],
        );
      case Obj.gSlider:
        return const PatcherNodeSnapshot(
          inputs: 0,
          outputs: 1,
          inputKinds: [],
          outputKinds: [PatchPortKind.control],
        );
    }
    return const PatcherNodeSnapshot(
      inputs: 0,
      outputs: 0,
      inputKinds: [],
      outputKinds: [],
    );
  }

  /// A small representative catalogue, including a `patcher` entry so tests
  /// can assert [objectTypes] filters it out.
  static final List<PatchObjectDescriptor> _defaultCatalogue = [
    const PatchObjectDescriptor(
      type: Obj.patcher,
      description: 'subpatch',
      category: PatchObjectCategory.generic,
      isDsp: false,
      inlets: [],
      outlets: [],
      params: [],
    ),
    const PatchObjectDescriptor(
      type: Obj.dSine,
      description: 'sine oscillator',
      category: PatchObjectCategory.oscillator,
      isDsp: true,
      inlets: [
        PatchInletDescriptor(
          label: 'freq',
          doc: 'frequency in Hz',
          range: '0..20000',
          accepts: {PatchInletAccept.buffer, PatchInletAccept.float},
        ),
      ],
      outlets: [
        PatchOutletDescriptor(
          label: 'out',
          doc: 'signal',
          range: '',
          type: PatchOutletType.buffer,
        ),
      ],
      params: [
        PatchParamDescriptor(
          name: 'frequency',
          doc: 'initial frequency',
          defaultValue: '440',
          range: '0..20000',
        ),
      ],
    ),
    const PatchObjectDescriptor(
      type: Obj.gSlider,
      description: 'horizontal slider',
      category: PatchObjectCategory.gui,
      isDsp: false,
      inlets: [],
      outlets: [
        PatchOutletDescriptor(
          label: 'out',
          doc: 'value',
          range: '0..1',
          type: PatchOutletType.float,
        ),
      ],
      params: [],
    ),
    const PatchObjectDescriptor(
      type: Obj.dDac,
      description: 'audio output',
      category: PatchObjectCategory.generic,
      isDsp: true,
      inlets: [
        PatchInletDescriptor(
          label: 'in',
          doc: 'signal',
          range: '',
          accepts: {PatchInletAccept.buffer},
        ),
      ],
      outlets: [],
      params: [],
    ),
  ];
}

/// One patcher instance's in-memory state.
class FakeInstance {
  FakeInstance({required this.mainOutputs});

  final int mainOutputs;
  final Map<int, FakeNode> nodes = {};
  final List<FakeCable> cables = [];
  final Set<String> receivers = {};
  bool mounted = false;
  int? mountedBus;
}

class FakeNode {
  FakeNode({required this.type, required this.args});
  final String type;

  /// Creation-argument string — mutable so [FakePatcherGateway.setParams] can
  /// reconfigure the object, mirroring yse's `setParams`.
  String args;

  /// Live GUI display value (yse's `guiValue`). Updated by a `sendFloat` into
  /// inlet 0; a test can also set it directly to simulate a cable-driven change.
  String guiValue = '';

  Offset? position;
  final Map<int, double> lastValueByInlet = {};
  final List<int> bangedInlets = [];
}

class FakeCable {
  FakeCable({
    required this.fromHandleId,
    required this.outlet,
    required this.toHandleId,
    required this.inlet,
  });
  final int fromHandleId;
  final int outlet;
  final int toHandleId;
  final int inlet;
}
