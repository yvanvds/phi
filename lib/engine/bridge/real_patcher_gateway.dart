import 'dart:ui';

import 'package:yse/yse.dart';

import '../../domain/patcher/patch_port_kind.dart';
import 'patcher_gateway.dart';
import 'patcher_node_snapshot.dart';

/// Production [PatcherGateway] that forwards every call to `package:yse`'s
/// `Patcher` and `Sound.fromPatcher`.
///
/// Owns one [Patcher] and at most one [Sound] mounting it. Requires
/// `libyse.dll` discoverable at runtime — see README.md.
class RealPatcherGateway implements PatcherGateway {
  Patcher? _patcher;
  Sound? _mounted;
  final Map<int, PHandle> _handles = {};

  Patcher get _p {
    final p = _patcher;
    if (p == null) {
      throw StateError('RealPatcherGateway used before init()');
    }
    return p;
  }

  @override
  void init({int mainOutputs = 2}) {
    _patcher = Patcher(mainOutputs: mainOutputs);
  }

  @override
  void dispose() {
    _mounted?.stop();
    _mounted?.dispose();
    _mounted = null;
    _patcher?.dispose();
    _patcher = null;
    _handles.clear();
  }

  @override
  int createObject(String type, {String args = ''}) {
    final h = _p.createObject(type, args: args);
    final id = h.id;
    _handles[id] = h;
    return id;
  }

  @override
  void deleteObject(int handleId) {
    final h = _handles.remove(handleId);
    if (h == null) return;
    _p.deleteObject(h);
  }

  @override
  void connect({
    required int fromHandleId,
    required int outlet,
    required int toHandleId,
    required int inlet,
  }) {
    final from = _handles[fromHandleId];
    final to = _handles[toHandleId];
    if (from == null || to == null) return;
    _p.connect(from, outlet: outlet, to: to, inlet: inlet);
  }

  @override
  void disconnect({
    required int fromHandleId,
    required int outlet,
    required int toHandleId,
    required int inlet,
  }) {
    final from = _handles[fromHandleId];
    final to = _handles[toHandleId];
    if (from == null || to == null) return;
    _p.disconnect(from, outlet: outlet, to: to, inlet: inlet);
  }

  @override
  PatcherNodeSnapshot inspect(int handleId) {
    final h = _handles[handleId]!;
    return PatcherNodeSnapshot(
      inputs: h.inputs,
      outputs: h.outputs,
      inputKinds: [
        for (var i = 0; i < h.inputs; i++)
          h.isDspInput(i) ? PatchPortKind.audio : PatchPortKind.control,
      ],
      outputKinds: [
        for (var i = 0; i < h.outputs; i++)
          h.outputDataType(i) == OutType.buffer
              ? PatchPortKind.audio
              : PatchPortKind.control,
      ],
    );
  }

  @override
  void setNodePosition(int handleId, Offset position) {
    final h = _handles[handleId];
    if (h == null) return;
    h
      ..setGuiProperty('x', position.dx.toString())
      ..setGuiProperty('y', position.dy.toString());
  }

  @override
  Offset? getNodePosition(int handleId) {
    final h = _handles[handleId];
    if (h == null) return null;
    final x = double.tryParse(h.getGuiProperty('x'));
    final y = double.tryParse(h.getGuiProperty('y'));
    if (x == null || y == null) return null;
    return Offset(x, y);
  }

  @override
  void sendFloat(int handleId, int inlet, double value) {
    _handles[handleId]?.sendFloat(inlet, value);
  }

  @override
  void mountAsSound({double volume = 1.0}) {
    _mounted?.stop();
    _mounted?.dispose();
    _mounted = Sound.fromPatcher(_p, volume: volume)..play();
  }

  @override
  String dumpJson() => _p.dumpJson();

  @override
  void parseJson(String content) {
    _p.parseJson(content);
    // Rebuild the handle table — ids may have shifted across parse.
    _handles.clear();
    for (var i = 0; i < _p.objects; i++) {
      final h = _p.getHandleAt(i);
      _handles[h.id] = h;
    }
  }
}
