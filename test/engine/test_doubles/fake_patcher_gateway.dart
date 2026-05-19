import 'dart:ui';

import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/engine/bridge/patcher_gateway.dart';
import 'package:phi/engine/bridge/patcher_node_snapshot.dart';
import 'package:yse/yse.dart';

/// In-memory [PatcherGateway] used in unit and widget tests.
///
/// Records every call so tests can assert call sequences, and stores a
/// minimal per-object state so the controller can be exercised end-to-end
/// without touching `package:yse` or its native library.
class FakePatcherGateway implements PatcherGateway {
  final List<String> calls = [];
  bool initialised = false;
  bool mounted = false;
  int mainOutputs = 0;

  final Map<int, FakeNode> nodes = {};
  final List<FakeCable> cables = [];
  int _nextId = 1;

  /// Override the default port topology for a given object type. Tests
  /// can stub e.g. an exotic node with custom inlet/outlet counts.
  final Map<String, PatcherNodeSnapshot> topologyOverrides = {};

  @override
  void init({int mainOutputs = 2}) {
    calls.add('init:$mainOutputs');
    initialised = true;
    this.mainOutputs = mainOutputs;
  }

  @override
  void dispose() {
    calls.add('dispose');
    initialised = false;
    mounted = false;
    nodes.clear();
    cables.clear();
  }

  @override
  int createObject(String type, {String args = ''}) {
    final id = _nextId++;
    calls.add('createObject:$id:$type:$args');
    nodes[id] = FakeNode(type: type, args: args);
    return id;
  }

  @override
  void deleteObject(int handleId) {
    calls.add('deleteObject:$handleId');
    nodes.remove(handleId);
    cables.removeWhere(
      (c) => c.fromHandleId == handleId || c.toHandleId == handleId,
    );
  }

  @override
  void connect({
    required int fromHandleId,
    required int outlet,
    required int toHandleId,
    required int inlet,
  }) {
    calls.add('connect:$fromHandleId:$outlet->$toHandleId:$inlet');
    cables.add(
      FakeCable(
        fromHandleId: fromHandleId,
        outlet: outlet,
        toHandleId: toHandleId,
        inlet: inlet,
      ),
    );
  }

  @override
  void disconnect({
    required int fromHandleId,
    required int outlet,
    required int toHandleId,
    required int inlet,
  }) {
    calls.add('disconnect:$fromHandleId:$outlet->$toHandleId:$inlet');
    cables.removeWhere(
      (c) =>
          c.fromHandleId == fromHandleId &&
          c.outlet == outlet &&
          c.toHandleId == toHandleId &&
          c.inlet == inlet,
    );
  }

  @override
  PatcherNodeSnapshot inspect(int handleId) {
    final type = nodes[handleId]?.type ?? '';
    final override = topologyOverrides[type];
    if (override != null) return override;
    return _defaultTopologyFor(type);
  }

  @override
  void setNodePosition(int handleId, Offset position) {
    calls.add(
      'setNodePosition:$handleId:${position.dx.toStringAsFixed(1)}'
      ':${position.dy.toStringAsFixed(1)}',
    );
    nodes[handleId]?.position = position;
  }

  @override
  Offset? getNodePosition(int handleId) => nodes[handleId]?.position;

  @override
  void sendFloat(int handleId, int inlet, double value) {
    calls.add('sendFloat:$handleId:$inlet:${value.toStringAsFixed(3)}');
    nodes[handleId]?.lastValueByInlet[inlet] = value;
  }

  @override
  void mountAsSound({double volume = 1.0}) {
    calls.add('mountAsSound:${volume.toStringAsFixed(3)}');
    mounted = true;
  }

  @override
  String dumpJson() => '{"objects":${nodes.length},"cables":${cables.length}}';

  @override
  void parseJson(String content) {
    calls.add('parseJson:${content.length}');
  }

  /// Default topology for the node types the first PR registers — keeps
  /// tests realistic without stubbing on every call.
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
}

class FakeNode {
  FakeNode({required this.type, required this.args});
  final String type;
  final String args;
  Offset? position;
  final Map<int, double> lastValueByInlet = {};
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
