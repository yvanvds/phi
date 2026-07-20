import 'dart:ui';

import 'package:yse/yse.dart';

import '../../domain/patcher/patch_port_kind.dart';
import 'patch_object_descriptor.dart';
import 'patcher_gateway.dart';
import 'patcher_node_snapshot.dart';
import 'real_materialised_synth.dart' show MixBusResolver;

/// Production [PatcherGateway] that forwards every call to `package:yse`'s
/// `Patcher` and `Sound.fromPatcher`.
///
/// Owns one [_PatcherInstance] per open `patch.` entity, keyed by the id
/// [createInstance] hands out; each holds its native [Patcher], its handle
/// table, and at most one [Sound] mounting it on a mix bus. The
/// [MixBusResolver] seam — supplied by the engine, defaulting to the master
/// bus — turns a mix-bus channel id into the live [Channel] a
/// `Sound.fromPatcher` attaches to, exactly as [RealSynthGateway] does.
///
/// Requires `libyse.dll` discoverable at runtime — see README.md.
class RealPatcherGateway implements PatcherGateway {
  RealPatcherGateway({MixBusResolver? busResolver})
    : _busResolver = busResolver ?? _masterBus;

  static Channel? _masterBus(int _) => null;

  final MixBusResolver _busResolver;

  final Map<int, _PatcherInstance> _instances = {};
  int _nextInstanceId = 1;

  _PatcherInstance _inst(int instanceId) {
    final inst = _instances[instanceId];
    if (inst == null) {
      throw StateError('RealPatcherGateway: unknown instance $instanceId');
    }
    return inst;
  }

  @override
  int createInstance({int mainOutputs = 2}) {
    final id = _nextInstanceId++;
    _instances[id] = _PatcherInstance(Patcher(mainOutputs: mainOutputs));
    return id;
  }

  @override
  void disposeInstance(int instanceId) {
    _instances.remove(instanceId)?.dispose();
  }

  @override
  void disposeAll() {
    for (final inst in _instances.values) {
      inst.dispose();
    }
    _instances.clear();
  }

  @override
  int createObject(int instanceId, String type, {String args = ''}) {
    final inst = _inst(instanceId);
    final h = inst.patcher.createObject(type, args: args);
    final id = h.id;
    inst.handles[id] = h;
    return id;
  }

  @override
  void deleteObject(int instanceId, int handleId) {
    final inst = _inst(instanceId);
    final h = inst.handles.remove(handleId);
    if (h == null) return;
    inst.patcher.deleteObject(h);
  }

  @override
  void connect(
    int instanceId, {
    required int fromHandleId,
    required int outlet,
    required int toHandleId,
    required int inlet,
  }) {
    final inst = _inst(instanceId);
    final from = inst.handles[fromHandleId];
    final to = inst.handles[toHandleId];
    if (from == null || to == null) return;
    inst.patcher.connect(from, outlet: outlet, to: to, inlet: inlet);
  }

  @override
  void disconnect(
    int instanceId, {
    required int fromHandleId,
    required int outlet,
    required int toHandleId,
    required int inlet,
  }) {
    final inst = _inst(instanceId);
    final from = inst.handles[fromHandleId];
    final to = inst.handles[toHandleId];
    if (from == null || to == null) return;
    inst.patcher.disconnect(from, outlet: outlet, to: to, inlet: inlet);
  }

  @override
  PatcherNodeSnapshot inspect(int instanceId, int handleId) {
    final h = _inst(instanceId).handles[handleId]!;
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
  void setNodePosition(int instanceId, int handleId, Offset position) {
    final h = _inst(instanceId).handles[handleId];
    if (h == null) return;
    h
      ..setGuiProperty('x', position.dx.toString())
      ..setGuiProperty('y', position.dy.toString());
  }

  @override
  Offset? getNodePosition(int instanceId, int handleId) {
    final h = _inst(instanceId).handles[handleId];
    if (h == null) return null;
    final x = double.tryParse(h.getGuiProperty('x'));
    final y = double.tryParse(h.getGuiProperty('y'));
    if (x == null || y == null) return null;
    return Offset(x, y);
  }

  @override
  void sendFloat(int instanceId, int handleId, int inlet, double value) {
    _inst(instanceId).handles[handleId]?.sendFloat(inlet, value);
  }

  @override
  void sendBang(int instanceId, int handleId, int inlet) {
    _inst(instanceId).handles[handleId]?.sendBang(inlet);
  }

  @override
  String guiValue(int instanceId, int handleId) =>
      _inst(instanceId).handles[handleId]?.guiValue ?? '';

  @override
  void setParams(int instanceId, int handleId, String args) {
    _inst(instanceId).handles[handleId]?.setParams(args);
  }

  @override
  bool passBang(int instanceId, String to) =>
      _inst(instanceId).patcher.passBang(to);

  @override
  bool passInt(int instanceId, int value, String to) =>
      _inst(instanceId).patcher.passInt(value, to);

  @override
  bool passFloat(int instanceId, double value, String to) =>
      _inst(instanceId).patcher.passFloat(value, to);

  @override
  bool passString(int instanceId, String value, String to) =>
      _inst(instanceId).patcher.passString(value, to);

  @override
  void mountAsSource(int instanceId, {int? busChannelId, double volume = 1.0}) {
    final inst = _inst(instanceId);
    inst.unmount();
    final bus = busChannelId == null ? null : _busResolver(busChannelId);
    inst.mounted = Sound.fromPatcher(inst.patcher, channel: bus, volume: volume)
      ..play();
  }

  @override
  void unmountSource(int instanceId) => _inst(instanceId).unmount();

  @override
  String dumpJson(int instanceId) => _inst(instanceId).patcher.dumpJson();

  @override
  void parseJson(int instanceId, String content) {
    final inst = _inst(instanceId);
    inst.patcher.parseJson(content);
    // Rebuild the handle table — ids may have shifted across parse.
    inst.handles.clear();
    for (var i = 0; i < inst.patcher.objects; i++) {
      final h = inst.patcher.getHandleAt(i);
      inst.handles[h.id] = h;
    }
  }

  @override
  List<PatchObjectDescriptor> objectTypes() => [
    for (final t in PatcherRegistry.types())
      // The subpatcher object is hidden from the palette in v1: no dive-in
      // editing means showing it would be a trap (design §10 decision 2).
      if (t.name != Obj.patcher) _descriptorFor(t),
  ];

  PatchObjectDescriptor _descriptorFor(PatcherObjectType t) =>
      PatchObjectDescriptor(
        type: t.name,
        description: t.description,
        category: _category(t.category),
        isDsp: t.isDsp,
        inlets: [
          for (final i in t.inlets())
            PatchInletDescriptor(
              label: i.label,
              doc: i.doc,
              range: i.range,
              accepts: {for (final a in i.accepts) _accept(a)},
            ),
        ],
        outlets: [
          for (final o in t.outlets())
            PatchOutletDescriptor(
              label: o.label,
              doc: o.doc,
              range: o.range,
              type: _outletType(o.type),
            ),
        ],
        params: [
          for (final p in t.params())
            PatchParamDescriptor(
              name: p.name,
              doc: p.doc,
              defaultValue: p.defaultValue,
              range: p.range,
            ),
        ],
      );

  PatchObjectCategory _category(PCategory c) => switch (c) {
    PCategory.unset => PatchObjectCategory.unset,
    PCategory.oscillator => PatchObjectCategory.oscillator,
    PCategory.filter => PatchObjectCategory.filter,
    PCategory.math => PatchObjectCategory.math,
    PCategory.generic => PatchObjectCategory.generic,
    PCategory.gui => PatchObjectCategory.gui,
    PCategory.time => PatchObjectCategory.time,
    PCategory.midi => PatchObjectCategory.midi,
  };

  PatchOutletType _outletType(OutType t) => switch (t) {
    OutType.invalid => PatchOutletType.invalid,
    OutType.bang => PatchOutletType.bang,
    OutType.float => PatchOutletType.float,
    OutType.integer => PatchOutletType.integer,
    OutType.buffer => PatchOutletType.buffer,
    OutType.list => PatchOutletType.list,
    OutType.any => PatchOutletType.any,
  };

  PatchInletAccept _accept(InletAccepts a) => switch (a) {
    InletAccepts.buffer => PatchInletAccept.buffer,
    InletAccepts.float => PatchInletAccept.float,
    InletAccepts.integer => PatchInletAccept.integer,
    InletAccepts.bang => PatchInletAccept.bang,
    InletAccepts.list => PatchInletAccept.list,
  };
}

/// One open patcher: its native [Patcher], handle table, and at most one
/// [Sound] mounting it on a mix bus.
class _PatcherInstance {
  _PatcherInstance(this.patcher);

  final Patcher patcher;
  final Map<int, PHandle> handles = {};
  Sound? mounted;

  void unmount() {
    mounted?.stop();
    mounted?.dispose();
    mounted = null;
  }

  void dispose() {
    // Sound before patcher: the audio thread renders the patcher *through*
    // the sound, so the sound must be gone first.
    unmount();
    patcher.dispose();
    handles.clear();
  }
}
