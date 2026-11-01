import 'dart:convert';
import 'dart:ui';

import 'package:phi/domain/patcher/item_list_args.dart';
import 'package:phi/domain/patcher/multislider_args.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/domain/patcher/slider_range.dart';
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

  /// Models the engine-direct patcher bus (issue #318): a **named** instance
  /// registers here (kind-stripped bus name → instance id) so a publish to
  /// `patcher.<name>.<slot>` — see [deliverToPatcherBus] — resolves to it.
  /// Anonymous instances never register and are unreachable.
  final Map<String, int> _patcherBus = {};

  /// Override the default port topology for a given object type. Tests can
  /// stub e.g. an exotic node with custom inlet/outlet counts.
  final Map<String, PatcherNodeSnapshot> topologyOverrides = {};

  /// Resolve an object's topology from its type **and its current arguments** —
  /// models the engine objects whose arity follows their creation arguments
  /// (a `.select 1 2 3` grows an outlet per argument), so a test can drive a
  /// [setParams] that reshapes the very object the canvas is drawing
  /// (issue #356). Returning null falls through to [topologyOverrides] and then
  /// the built-in defaults.
  PatcherNodeSnapshot? Function(String type, String args)? topologyResolver;

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

  /// Mirrors the engine's patcher-name cap; a test may lower it.
  @override
  int maxInstanceNameLength = Patcher.maxNameLength;

  @override
  int createInstance({int mainOutputs = 2, String name = ''}) {
    final id = _nextInstanceId++;
    calls.add('createInstance:$id:$mainOutputs');
    instances[id] = FakeInstance(mainOutputs: mainOutputs, busName: name);
    // A named instance registers on the engine-direct patcher bus (issue #318);
    // last registration wins, so a rename (new instance, new name) re-registers.
    // An over-long name opens anonymous, exactly as the real gateway does
    // (issue #452).
    if (name.isNotEmpty && name.length <= maxInstanceNameLength) {
      _patcherBus[name] = id;
    }
    return id;
  }

  @override
  void disposeInstance(int instanceId) {
    calls.add('disposeInstance:$instanceId');
    final inst = instances.remove(instanceId);
    if (inst != null && _patcherBus[inst.busName] == instanceId) {
      _patcherBus.remove(inst.busName);
    }
  }

  @override
  void disposeAll() {
    calls.add('disposeAll');
    instances.clear();
    _patcherBus.clear();
  }

  /// Model an engine-direct publish to the patcher bus [address]
  /// (`patcher.<name>.<slot>`): resolve the instance registered under `<name>`
  /// and record [value] at its `<slot>`, returning whether one was reachable
  /// there (issue #318). Stands in for the native engine routing a
  /// `patch.<name>.send(slot, v)` verb to the patcher named `<name>`; an
  /// anonymous (unregistered) target returns false.
  bool deliverToPatcherBus(String address, double value) {
    const prefix = 'patcher.';
    if (!address.startsWith(prefix)) return false;
    final rest = address.substring(prefix.length);
    final lastDot = rest.lastIndexOf('.');
    if (lastDot <= 0) return false;
    final name = rest.substring(0, lastDot);
    final slot = int.tryParse(rest.substring(lastDot + 1));
    if (slot == null) return false;
    final id = _patcherBus[name];
    if (id == null) return false;
    instances[id]!.busSlots[slot] = value;
    return true;
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
    final node = _inst(instanceId).nodes[handleId];
    final type = node?.type ?? '';
    final resolved = topologyResolver?.call(type, node?.args ?? '');
    if (resolved != null) return resolved;
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
  void setGuiProperty(int instanceId, int handleId, String key, String value) {
    calls.add('setGuiProperty:$handleId:$key:$value');
    final node = _inst(instanceId).nodes[handleId];
    if (node == null) return;
    value.isEmpty ? node.gui.remove(key) : node.gui[key] = value;
  }

  @override
  String guiProperty(int instanceId, int handleId, String key) =>
      _inst(instanceId).nodes[handleId]?.gui[key] ?? '';

  @override
  void sendFloat(int instanceId, int handleId, int inlet, double value) {
    calls.add('sendFloat:$handleId:$inlet:${value.toStringAsFixed(3)}');
    final node = _inst(instanceId).nodes[handleId];
    if (node == null) return;
    if (node.isItemList) {
      node.lastValueByInlet[inlet] = value;
      _itemListNumber(instanceId, handleId, inlet, value);
      return;
    }
    if (node.isMultiValueSlider) {
      node.lastValueByInlet[inlet] = value;
      _multiValueSliderNumber(instanceId, handleId, inlet, value);
      return;
    }
    // Model the engine's uncoerced inlet dispatch (issue #439): `gToggle`
    // registers int and bang handlers but **no float one**, so a float sent at
    // it lands nowhere — the real engine drops it silently. The fake dropping
    // it too is what lets a test catch a body pushing through the wrong verb.
    if (node.type == Obj.gToggle) return;
    node.lastValueByInlet[inlet] = value;
    if (inlet == 0 && node.receiveSwitchNumber(value)) return;
    // A `.dial` stores its position clamped to 0–1, as `gDial::Store` does.
    if (node.type == Obj.gDial && inlet == 0) {
      node.guiValue = _formatGui(value.clamp(0.0, 1.0));
      return;
    }
    // A control object's "hot" inlet (0) drives its display value — a slider
    // or number reflects the last value set into it, exactly what the native
    // side reports back through `guiValue`.
    if (inlet == 0) node.guiValue = _formatGui(value);
  }

  @override
  void sendInt(int instanceId, int handleId, int inlet, int value) {
    calls.add('sendInt:$handleId:$inlet:$value');
    final node = _inst(instanceId).nodes[handleId];
    if (node == null) return;
    node.lastValueByInlet[inlet] = value.toDouble();
    if (node.isItemList) {
      _itemListNumber(instanceId, handleId, inlet, value.toDouble());
      return;
    }
    if (node.isMultiValueSlider) {
      _multiValueSliderNumber(instanceId, handleId, inlet, value.toDouble());
      return;
    }
    if (inlet != 0) return;
    if (node.receiveSwitchNumber(value.toDouble())) return;
    // The engine's `gToggle` displays its state as `on`/`off`, not as a
    // number (issue #439) — the fake reports the same strings so a body that
    // only parses digits fails here the way it fails against libyse.
    node.guiValue = node.type == Obj.gToggle
        ? (value != 0 ? 'on' : 'off')
        : '$value';
  }

  @override
  void sendBang(int instanceId, int handleId, int inlet) {
    calls.add('sendBang:$handleId:$inlet');
    final node = _inst(instanceId).nodes[handleId];
    if (node == null) return;
    node.bangedInlets.add(inlet);
    // An item list re-sends on a bang (`gItemListBase`).
    if (inlet == 0 && node.isItemList) _emitItemList(instanceId, handleId);
    // So does a multi-value slider (`gRSlider` / `gXYSlider` /
    // `gMultiSlider`): the hot inlet calculates after every message.
    if (inlet == 0 && node.isMultiValueSlider) {
      _emitMultiValueSlider(instanceId, handleId);
    }
    // A latching `.led` / `.textbutton` flips on a bang; a momentary one
    // takes it as a press (`gLabelSwitchBase`).
    if (inlet == 0 && node.isLabelSwitch) {
      node.guiValue = node.isMomentary || node.guiValue != '1' ? '1' : '0';
    }
  }

  /// A momentary `.led` / `.textbutton`'s read is **destructive**, as libYSE's
  /// is (`gLabelSwitchBase`'s `GUI_VALUE`): it reports a pending press as `1`
  /// and clears it in the same call, so a second read in the same frame says
  /// `0` (issue #514). Reading [FakeNode.guiValue] directly in a test is a
  /// look, not a consume.
  @override
  String guiValue(int instanceId, int handleId) {
    final node = _inst(instanceId).nodes[handleId];
    if (node == null) return '';
    final value = node.guiValue;
    node.consumePress();
    return value;
  }

  @override
  void sendList(int instanceId, int handleId, int inlet, String list) {
    calls.add('sendList:$handleId:$inlet:$list');
    final node = _inst(instanceId).nodes[handleId];
    node?.receiveList(inlet, list);
    if (inlet == 0 && (node?.isItemList ?? false)) {
      _emitItemList(instanceId, handleId);
    }
    if (inlet == 0 && (node?.isMultiValueSlider ?? false)) {
      _emitMultiValueSlider(instanceId, handleId);
    }
  }

  @override
  void sendMessage(int instanceId, int handleId, int inlet, String message) {
    calls.add('sendMessage:$handleId:$inlet:$message');
    // Same native call as a list, exactly as the real gateway sends it.
    final node = _inst(instanceId).nodes[handleId];
    node?.receiveList(inlet, message);
    if (inlet == 0 && (node?.isItemList ?? false)) {
      _emitItemList(instanceId, handleId);
    }
    if (inlet == 0 && (node?.isMultiValueSlider ?? false)) {
      _emitMultiValueSlider(instanceId, handleId);
    }
  }

  /// A number landing on an item list (`gItemListBase::FloatIn`): on inlet 0
  /// it touches that item, and the hot inlet sends either way.
  void _itemListNumber(int instanceId, int handleId, int inlet, double value) {
    if (inlet != 0) return;
    _inst(instanceId).nodes[handleId]!.touchItem(value);
    _emitItemList(instanceId, handleId);
  }

  /// Model an item list's send (`gItemListBase`'s `CALC`), right to left as
  /// the engine fires it: the whole selection on outlet 2, the pointed-at
  /// item's name on outlet 1, its number on outlet 0 — each delivered down
  /// every cable from that outlet, so a connected `.i` follows outlet 0.
  void _emitItemList(int instanceId, int handleId) {
    final inst = _inst(instanceId);
    final node = inst.nodes[handleId]!;
    final at = node.itemCurrent;
    final label = node.itemArgs.labels[at];
    final state = node.guiValue;
    void deliver(int outlet, void Function(FakeCable c) send) {
      for (final c in [...inst.cables]) {
        if (c.fromHandleId == handleId && c.outlet == outlet) send(c);
      }
    }

    deliver(2, (c) => sendList(instanceId, c.toHandleId, c.inlet, state));
    deliver(1, (c) => sendList(instanceId, c.toHandleId, c.inlet, label));
    deliver(0, (c) => sendInt(instanceId, c.toHandleId, c.inlet, at));
  }

  /// A number landing on a multi-value slider: stored by the node, and on the
  /// hot inlet sent on.
  void _multiValueSliderNumber(
    int instanceId,
    int handleId,
    int inlet,
    double value,
  ) {
    _inst(instanceId).nodes[handleId]!.receiveSliderNumber(inlet, value);
    if (inlet == 0) _emitMultiValueSlider(instanceId, handleId);
  }

  /// Model a multi-value slider's send (`CALC`), right to left as the engine
  /// fires it, each delivered down every cable from that outlet:
  ///
  /// - `.rslider` / `.xyslider`: the pair as a list on outlet 2, then the high
  ///   end (y) on outlet 1, then the low end (x) on outlet 0.
  /// - `.multislider`: a pending `fetch` answer on outlet 1 first (it is sent
  ///   from the handler), then the whole bank as a list on outlet 0.
  void _emitMultiValueSlider(int instanceId, int handleId) {
    final inst = _inst(instanceId);
    final node = inst.nodes[handleId]!;
    void deliver(int outlet, void Function(FakeCable c) send) {
      for (final c in [...inst.cables]) {
        if (c.fromHandleId == handleId && c.outlet == outlet) send(c);
      }
    }

    final cells = node.guiCells;
    if (node.type == Obj.gMultislider) {
      final fetched = node.takeFetched();
      if (fetched != null) {
        final value = double.parse(cells[fetched]);
        deliver(1, (c) => sendFloat(instanceId, c.toHandleId, c.inlet, value));
      }
      final bank = node.guiValue;
      deliver(0, (c) => sendList(instanceId, c.toHandleId, c.inlet, bank));
      return;
    }
    final pair = node.guiValue;
    final first = double.parse(cells[0]);
    final second = double.parse(cells[1]);
    deliver(2, (c) => sendList(instanceId, c.toHandleId, c.inlet, pair));
    deliver(1, (c) => sendFloat(instanceId, c.toHandleId, c.inlet, second));
    deliver(0, (c) => sendFloat(instanceId, c.toHandleId, c.inlet, first));
  }

  @override
  int guiValueCount(int instanceId, int handleId) =>
      _inst(instanceId).nodes[handleId]?.guiCells.length ?? 0;

  @override
  String guiValueAt(int instanceId, int handleId, int index) {
    final node = _inst(instanceId).nodes[handleId];
    final cells = node?.guiCells;
    if (cells == null || index < 0 || index >= cells.length) return '';
    final value = cells[index];
    node!.consumePress();
    return value;
  }

  @override
  bool guiValueIsSettable(int instanceId, int handleId) =>
      _inst(instanceId).nodes[handleId]?.guiSettable ?? false;

  @override
  bool restoreGuiValue(int instanceId, int handleId, String state) {
    final node = _inst(instanceId).nodes[handleId];
    if (node == null || !node.guiSettable) return false;
    // A restore *is* a list on inlet 0 (yse's `restoreGuiValue`), so it is
    // logged — and lands — as one.
    sendList(instanceId, handleId, 0, state);
    return true;
  }

  @override
  bool setGuiValueAt(int instanceId, int handleId, int index, String value) {
    final node = _inst(instanceId).nodes[handleId];
    if (node == null || !node.guiSettable) return false;
    if (index < 0 || index >= node.guiCells.length) return false;
    // yse's `setGuiValueAt`: `set <i> <v>`, or the whole text on a .textedit.
    sendList(
      instanceId,
      handleId,
      0,
      node.type == Obj.gTextedit ? value : 'set $index $value',
    );
    return true;
  }

  @override
  void setParams(int instanceId, int handleId, String args) {
    calls.add('setParams:$handleId:$args');
    final node = _inst(instanceId).nodes[handleId];
    if (node == null) return;
    node.args = args;
    // New items rebuild an item list (the engine replaces the object), so it
    // comes back with item 0 selected and every flag clear.
    if (node.isItemList) node.reshapeItems();
    // A multi-value slider survives a re-range (the scalar plan): its bounds
    // apply on the way out at once, and a `.multislider`'s `size` becomes its
    // live count, values kept.
    if (node.isMultiValueSlider) node.reconfigureSlider();
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
  /// (id · type · args · optional x/y and gui) and cables — so a flush → reload
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
            if (entry.value.gui.isNotEmpty) 'gui': entry.value.gui,
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
      final gui = raw['gui'];
      if (gui is Map) {
        node.gui.addAll({
          for (final e in gui.entries) '${e.key}': '${e.value}',
        });
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
      // Hot and cold inlets; low/x, high/y and the pair out (issue #472).
      case Obj.gRslider:
      case Obj.gXyslider:
        return const PatcherNodeSnapshot(
          inputs: 2,
          outputs: 3,
          inputKinds: [PatchPortKind.control, PatchPortKind.control],
          outputKinds: [
            PatchPortKind.control,
            PatchPortKind.control,
            PatchPortKind.control,
          ],
        );
      // One hot inlet; the bank and a fetched cell out (issue #472).
      case Obj.gMultislider:
        return const PatcherNodeSnapshot(
          inputs: 1,
          outputs: 2,
          inputKinds: [PatchPortKind.control],
          outputKinds: [PatchPortKind.control, PatchPortKind.control],
        );
      // One hot inlet; index, item name and whole selection out (issue #471).
      case Obj.gUmenu:
      case Obj.gRadiogroup:
      case Obj.gTab:
        return const PatcherNodeSnapshot(
          inputs: 1,
          outputs: 3,
          inputKinds: [PatchPortKind.control],
          outputKinds: [
            PatchPortKind.control,
            PatchPortKind.control,
            PatchPortKind.control,
          ],
        );
    }
    return const PatcherNodeSnapshot(
      inputs: 0,
      outputs: 0,
      inputKinds: [],
      outputKinds: [],
    );
  }

  /// The built-in catalogue, exposed so a test that needs one *extra* type can
  /// extend it (`objectTypesCatalogue = [...defaultCatalogue, mine]`) instead
  /// of restating every entry.
  static List<PatchObjectDescriptor> get defaultCatalogue =>
      List.unmodifiable(_defaultCatalogue);

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
  FakeInstance({required this.mainOutputs, this.busName = ''});

  final int mainOutputs;

  /// The engine-direct bus name this instance is registered under — the
  /// kind-stripped `patch.` address (issue #318). Empty = anonymous.
  final String busName;

  /// Values delivered engine-direct to `patcher.<busName>.<slot>`, keyed by
  /// slot — recorded by [FakePatcherGateway.deliverToPatcherBus].
  final Map<int, double> busSlots = {};

  final Map<int, FakeNode> nodes = {};
  final List<FakeCable> cables = [];
  final Set<String> receivers = {};
  bool mounted = false;
  int? mountedBus;
}

class FakeNode {
  FakeNode({required this.type, required this.args})
    : guiCells = _initialCells(type, args),
      guiSettable = !_unsettable.contains(type) && type.startsWith('.') {
    if (isMultiValueSlider) {
      _bankSize = MultisliderArgs.parse(args).size;
      _publishSlider();
    }
  }
  final String type;

  /// Creation-argument string — mutable so [FakePatcherGateway.setParams] can
  /// reconfigure the object, mirroring yse's `setParams`.
  String args;

  /// The live GUI state as cells (the GUI value protocol, issue #469) — one
  /// cell for a scalar control or an object without GUI state (that cell is
  /// then empty), two for `.rslider` / `.xyslider`, 128 for `.kslider`, the
  /// bank size for `.multislider`. A test may assign it directly to simulate a
  /// cable-driven change to a multi-cell control.
  List<String> guiCells;

  /// Whether the object accepts its GUI state back (yse's
  /// `guiValueIsSettable`). Defaults to the engine's answer: every `.`-control
  /// except `.b`, `.m` and `.l`; a test may override it.
  bool guiSettable;

  /// Live GUI display value (yse's `guiValue`): every cell, space-separated.
  /// Updated by a `sendFloat` into inlet 0; a test can also set it directly to
  /// simulate a cable-driven change, which makes it a one-cell state.
  String get guiValue => guiCells.join(' ');
  set guiValue(String value) => guiCells = [value];

  /// Whether this is a `.umenu` / `.radiogroup` / `.tab` (`gItemListBase`).
  bool get isItemList => _itemListTypes.contains(type);

  /// An item list's shape, read from its creation arguments.
  ItemListArgs get itemArgs => ItemListArgs.parse(args);

  /// The item an item list points at — the selection in single select, the
  /// item last touched with `multi`. What its outlet 0 sends.
  int itemCurrent = 0;

  /// Rebuild an item list's state for its current arguments
  /// (`gItemListBase::ShapeItems`): item 0, every flag clear.
  void reshapeItems() {
    guiCells = _itemCells(args);
    itemCurrent = 0;
  }

  /// "The user touched item [value]" (`gItemListBase::Touch`): selects it, or
  /// with `multi` toggles it, and points at it. An item the list does not have
  /// changes nothing.
  void touchItem(double value) {
    if (!(value >= 0)) return;
    final item = value.truncate();
    if (item >= itemArgs.count) return;
    if (itemArgs.multi) {
      guiCells = [...guiCells]..[item] = guiCells[item] == '0' ? '1' : '0';
    } else {
      guiCells = ['$item'];
    }
    itemCurrent = item;
  }

  /// A list on an item list's inlet 0 (`gItemListBase::ListIn`): `set <i> <v>`
  /// writes one cell outright, a leading name selects that item, and numbers
  /// are the whole state — the index, or with `multi` the flags positionally.
  void _receiveItemList(String list) {
    final tokens = list.trim().split(RegExp(r'\s+'));
    if (tokens.first.isEmpty) return;
    final items = itemArgs;
    if (tokens.first == 'set') {
      if (tokens.length < 3) return;
      final cell = num.tryParse(tokens[1]);
      final value = num.tryParse(tokens[2]);
      if (cell == null || value == null || cell < 0) return;
      final at = cell.truncate();
      if (items.multi) {
        if (at >= items.count) return;
        guiCells = [...guiCells]..[at] = value == 0 ? '0' : '1';
        itemCurrent = at;
        return;
      }
      if (at != 0 || value < 0) return;
      final item = value.truncate();
      if (item >= items.count) return;
      guiCells = ['$item'];
      itemCurrent = item;
      return;
    }
    final number = num.tryParse(tokens.first);
    if (number == null) {
      final at = items.labels.indexOf(tokens.first);
      if (at >= 0) touchItem(at.toDouble());
      return;
    }
    if (!items.multi) {
      touchItem(number.toDouble());
      return;
    }
    final flags = [...guiCells];
    var written = 0;
    for (final t in tokens) {
      if (written >= items.count) break;
      final flag = num.tryParse(t);
      if (flag == null) break;
      flags[written++] = flag == 0 ? '0' : '1';
    }
    if (written == 0) return;
    guiCells = flags;
    final lowest = flags.indexOf('1');
    if (lowest >= 0) itemCurrent = lowest;
  }

  /// A fresh item list's cells: the index alone, or one flag per item.
  static List<String> _itemCells(String args) {
    final items = ItemListArgs.parse(args);
    return items.multi ? List.filled(items.count, '0') : ['0'];
  }

  static const Set<String> _itemListTypes = {
    Obj.gUmenu,
    Obj.gRadiogroup,
    Obj.gTab,
  };

  /// Whether this is a `.led` / `.textbutton` (`gLabelSwitchBase`).
  bool get isLabelSwitch => type == Obj.gLed || type == Obj.gTextbutton;

  /// Whether this label switch was made `momentary` — its leading creation
  /// argument — so it registers presses rather than holding a state.
  bool get isMomentary =>
      isLabelSwitch && args.trim().split(RegExp(r'\s+')).first == 'momentary';

  /// Model a number landing on a label switch's inlet 0: a momentary one takes
  /// any number as a press, a latching one stores it as on (non-zero) / off.
  /// Returns whether the node was a label switch (and so handled it).
  bool receiveSwitchNumber(double value) {
    if (!isLabelSwitch) return false;
    guiValue = isMomentary || value != 0 ? '1' : '0';
    return true;
  }

  /// Clear a momentary label switch's pending press — what the engine does on
  /// every read of its GUI state. A no-op for anything else.
  void consumePress() {
    if (isMomentary) guiCells = ['0'];
  }

  /// Every list (and selector message) sent to the object, in order, keyed by
  /// inlet.
  final Map<int, List<String>> listsByInlet = {};

  Offset? position;

  /// Decoration GUI properties beyond the position — yse's `setGuiProperty`
  /// store, dumped under `gui` the way libYSE's own dump nests them.
  final Map<String, String> gui = {};
  final Map<int, double> lastValueByInlet = {};
  final List<int> bangedInlets = [];

  /// Model the engine taking a list (or selector message) on [inlet].
  ///
  /// Only inlet 0 of a settable control moves the GUI state, the way the
  /// real objects do: `set <i> <v>` writes one cell (dropped past the count),
  /// a `.textedit` takes the whole text as its one cell, and a list of numbers
  /// becomes the cells — so a list resizes a `.multislider` bank. `.incdec`'s
  /// `inc` / `dec` step it ([_stepIncdec]); any other selector (`clear`, ...)
  /// is object-specific behaviour the fake does not model: it is recorded and
  /// leaves the state alone. A `.l` (not
  /// settable) stores the list as its one cell.
  void receiveList(int inlet, String list) {
    listsByInlet.putIfAbsent(inlet, () => []).add(list);
    if (inlet != 0) return;
    if (type == Obj.gIncdec && _stepIncdec(list.trim())) return;
    if (isItemList) {
      _receiveItemList(list);
      return;
    }
    if (isMultiValueSlider) {
      _receiveSliderList(list);
      return;
    }
    if (type == Obj.gList) {
      guiCells = [list];
      return;
    }
    if (!guiSettable) return;
    if (type == Obj.gTextedit) {
      guiCells = [list];
      return;
    }
    final tokens = list.trim().split(RegExp(r'\s+'));
    if (tokens.first == 'set' && tokens.length >= 3) {
      final index = int.tryParse(tokens[1]);
      if (index == null || index < 0 || index >= guiCells.length) return;
      guiCells = [...guiCells]..[index] = tokens.skip(2).join(' ');
      return;
    }
    if (tokens.every((t) => num.tryParse(t) != null)) guiCells = tokens;
  }

  /// Model `.incdec`'s `inc` / `dec` selectors (`gIncDec::Move`): one step of
  /// its `step` argument, bounded by `minimum` / `maximum` (swapped when
  /// reversed), clamping or — with `wrap` — wrapping. Returns whether [message]
  /// was one of the two.
  bool _stepIncdec(String message) {
    if (message != 'inc' && message != 'dec') return false;
    final parts = args.trim().isEmpty
        ? const <String>[]
        : args.trim().split(RegExp(r'\s+'));
    int at(int i, int fallback) => i < parts.length
        ? (num.tryParse(parts[i])?.truncate() ?? fallback)
        : fallback;
    final step = at(0, 1);
    var lo = at(1, -2147483648);
    var hi = at(2, 2147483647);
    if (lo > hi) (lo, hi) = (hi, lo);
    final wrap = at(3, 0) != 0;
    final current = int.tryParse(guiValue) ?? 0;
    final next = current + (message == 'inc' ? step : -step);
    final int bounded;
    if (!wrap) {
      bounded = next.clamp(lo, hi);
    } else {
      final span = hi - lo + 1;
      bounded = lo + (next - lo) % span;
    }
    guiValue = '$bounded';
    return true;
  }

  // ─── the multi-value sliders (issue #472) ───────────────────────────

  /// Whether this is a `.rslider`, `.xyslider` or `.multislider` — the GUI
  /// controls whose state is several cells in their own bounded units.
  bool get isMultiValueSlider => _multiValueSliderTypes.contains(type);

  static const Set<String> _multiValueSliderTypes = {
    Obj.gRslider,
    Obj.gXyslider,
    Obj.gMultislider,
  };

  /// `.rslider`'s two ends in write order (not sorted: `first` is what inlet 0
  /// writes, `second` inlet 1), or `.xyslider`'s x and y.
  double _first = 0;
  double _second = 0;

  /// `.multislider`'s bank: allocated whole at the engine's 1024 cells, of
  /// which [_bankSize] are live — so a shrink hides the tail and a regrow shows
  /// it again, as `gMultiSlider` does.
  final List<double> _bank = List.filled(MultisliderArgs.maxSize, 0);
  int _bankSize = MultisliderArgs.defaultSize;

  /// A `fetch <i>` not yet answered — read once by the gateway's send.
  int? _fetched;

  /// The cell a `fetch` asked for, cleared by the read.
  int? takeFetched() {
    final at = _fetched;
    _fetched = null;
    return at;
  }

  SliderRange get _rangeX =>
      SliderRange.fromArgs(type == Obj.gMultislider ? _argsWithoutSize : args);
  SliderRange get _rangeY => SliderRange.fromArgs(args, at: 2);
  String get _argsWithoutSize {
    final parts = args.trim().split(RegExp(r'\s+'));
    return parts.length <= 1 ? '' : parts.skip(1).join(' ');
  }

  /// Clamp into [range], a NaN answered with the low bound (the engine's
  /// `Bound`).
  static double _bound(double value, SliderRange range) {
    if (!(value >= range.low)) return range.low;
    if (value > range.high) return range.high;
    return value;
  }

  /// Re-render the cells from the stored state, bounded and (for `.rslider`)
  /// sorted on the way out, as the engine reports them.
  void _publishSlider() {
    switch (type) {
      case Obj.gRslider:
        final a = _bound(_first, _rangeX);
        final b = _bound(_second, _rangeX);
        guiCells = [_spell(a < b ? a : b), _spell(a < b ? b : a)];
      case Obj.gXyslider:
        guiCells = [
          _spell(_bound(_first, _rangeX)),
          _spell(_bound(_second, _rangeY)),
        ];
      case Obj.gMultislider:
        guiCells = [
          for (var i = 0; i < _bankSize; i++) _spell(_bound(_bank[i], _rangeX)),
        ];
    }
  }

  static String _spell(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  /// The object's parameters changed (`setParams`).
  void reconfigureSlider() {
    if (type == Obj.gMultislider) {
      _bankSize = MultisliderArgs.parse(args).size;
    }
    _publishSlider();
  }

  /// A number on [inlet]: `.rslider` one end (inlet 0) or the other (inlet 1),
  /// `.xyslider` x or y, `.multislider` every live cell.
  void receiveSliderNumber(int inlet, double value) {
    if (type == Obj.gMultislider) {
      if (inlet != 0) return;
      final bounded = _bound(value, _rangeX);
      for (var i = 0; i < _bankSize; i++) {
        _bank[i] = bounded;
      }
    } else if (inlet == 0) {
      _first = _bound(value, _rangeX);
    } else {
      _second = _bound(value, type == Obj.gXyslider ? _rangeY : _rangeX);
    }
    _publishSlider();
  }

  /// A list on inlet 0: `set <i> <v>` writes one cell, `.multislider`'s
  /// `fetch <i>` asks for one, and otherwise the numbers are the whole state —
  /// the first two for a pair, every one (resizing the bank) for a
  /// `.multislider`. Non-numeric tokens are skipped, as the engine's parser
  /// skips them.
  void _receiveSliderList(String list) {
    final tokens = list.trim().split(RegExp(r'\s+'));
    if (tokens.first.isEmpty) return;
    final numbers = [for (final t in tokens) ?double.tryParse(t)];
    final keyword = tokens.first;
    if (keyword == 'set' || keyword == 'fetch') {
      if (numbers.isEmpty || !(numbers[0] >= 0)) return;
      final at = numbers[0].truncate();
      if (keyword == 'fetch') {
        if (type == Obj.gMultislider && at < _bankSize) _fetched = at;
        return;
      }
      if (numbers.length < 2) return;
      final value = numbers[1];
      switch (type) {
        case Obj.gRslider:
          if (at > 1) return;
          // The index names a presented cell, not a storage slot.
          final firstIsLow =
              !(_bound(_second, _rangeX) < _bound(_first, _rangeX));
          if ((at == 0) == firstIsLow) {
            _first = _bound(value, _rangeX);
          } else {
            _second = _bound(value, _rangeX);
          }
        case Obj.gXyslider:
          if (at > 1) return;
          if (at == 0) {
            _first = _bound(value, _rangeX);
          } else {
            _second = _bound(value, _rangeY);
          }
        case Obj.gMultislider:
          if (at >= _bankSize) return;
          _bank[at] = _bound(value, _rangeX);
      }
      _publishSlider();
      return;
    }
    if (numbers.isEmpty) return;
    if (type == Obj.gMultislider) {
      final count = numbers.length.clamp(0, MultisliderArgs.maxSize);
      for (var i = 0; i < count; i++) {
        _bank[i] = _bound(numbers[i], _rangeX);
      }
      _bankSize = count;
    } else {
      _first = _bound(numbers[0], _rangeX);
      if (numbers.length >= 2) {
        _second = _bound(numbers[1], type == Obj.gXyslider ? _rangeY : _rangeX);
      }
    }
    _publishSlider();
  }

  /// Objects whose GUI value the engine does not accept back.
  static const Set<String> _unsettable = {Obj.gButton, Obj.gMessage, Obj.gList};

  /// The cell layout a fresh object reports, mirroring the engine's.
  static List<String> _initialCells(String type, String args) {
    switch (type) {
      case Obj.gRslider:
      case Obj.gXyslider:
        return ['0', '0'];
      case Obj.gKslider:
        return List.filled(128, '0');
      // The #470 scalar controls start at 0 / off, as the engine reports them
      // (a `.dial` spells it `0.000000`; callers compare numbers).
      case Obj.gDial:
      case Obj.gIncdec:
      case Obj.gLed:
      case Obj.gTextbutton:
        return ['0'];
      // A fresh `.textedit` holds its `text` argument, joined with spaces.
      case Obj.gTextedit:
        return [args.trim().split(RegExp(r'\s+')).join(' ')];
      case Obj.gUmenu:
      case Obj.gRadiogroup:
      case Obj.gTab:
        return _itemCells(args);
      case Obj.gMultislider:
        final size = int.tryParse(args.trim().split(RegExp(r'\s+')).first);
        return List.filled(size ?? 8, '0');
    }
    return [''];
  }
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
