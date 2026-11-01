import 'dart:convert';
import 'dart:ui';

import 'package:phi/domain/patcher/field_node.dart';
import 'package:phi/domain/patcher/function_args.dart';
import 'package:phi/domain/patcher/function_point.dart';
import 'package:phi/domain/patcher/item_list_args.dart';
import 'package:phi/domain/patcher/matrixctrl_args.dart';
import 'package:phi/domain/patcher/multislider_args.dart';
import 'package:phi/domain/patcher/nodes_args.dart';
import 'package:phi/domain/patcher/nodes_field.dart';
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
    if (node.isKeyboard || node.isStaff) {
      node.lastValueByInlet[inlet] = value;
      _musicalNumber(instanceId, handleId, inlet, value);
      return;
    }
    // `gMatrixCtrl` takes lists and bangs only, so a bare number is dropped.
    if (node.isGrid) return;
    // So does `gNodes`: a single number is not a position (issue #476).
    if (node.isNodes) return;
    // A `.function` reads a number as an x and answers its y (issue #475).
    if (node.isFunction) {
      if (inlet == 0) node.queryFunction(value);
      _emitFunction(instanceId, handleId);
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
    if (node.isKeyboard || node.isStaff) {
      _musicalNumber(instanceId, handleId, inlet, value.toDouble());
      return;
    }
    if (node.isGrid || node.isNodes) return;
    if (node.isFunction) {
      if (inlet == 0) node.queryFunction(value.toDouble());
      _emitFunction(instanceId, handleId);
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
    // A `.kslider` re-sends what it holds; a `.nslider` re-sends its note.
    if (inlet == 0 && node.isKeyboard) node.bangKeyboard();
    _emitMusical(instanceId, handleId, inlet: inlet);
    // A `.matrixctrl` sends every cell.
    if (inlet == 0 && node.isGrid) node.sendWholeGrid();
    _emitGrid(instanceId, handleId);
    // A `.function` sends its ramp.
    if (inlet == 0 && node.isFunction) node.sendRamp();
    _emitFunction(instanceId, handleId);
    // A `.nodes` re-sends against the cursor as it stands.
    if (inlet == 0 && node.isNodes) _emitNodes(instanceId, handleId);
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
    _emitMusical(instanceId, handleId, inlet: inlet);
    _emitGrid(instanceId, handleId);
    _emitFunction(instanceId, handleId);
    if (inlet == 0 && (node?.isNodes ?? false)) {
      _emitNodes(instanceId, handleId);
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
    _emitMusical(instanceId, handleId, inlet: inlet);
    _emitGrid(instanceId, handleId);
    _emitFunction(instanceId, handleId);
    if (inlet == 0 && (node?.isNodes ?? false)) {
      _emitNodes(instanceId, handleId);
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

  /// A number landing on a `.kslider` or `.nslider`, then whatever it sends.
  void _musicalNumber(int instanceId, int handleId, int inlet, double value) {
    final node = _inst(instanceId).nodes[handleId]!;
    if (node.isKeyboard) {
      node.receiveKeyboardNumber(inlet, value);
    } else {
      node.receiveStaffNumber(inlet, value);
    }
    _emitMusical(instanceId, handleId, inlet: inlet);
  }

  /// Model what a `.kslider` or `.nslider` sends after a message on [inlet],
  /// each value delivered down every cable from its outlet as an int:
  ///
  /// - `.kslider`: every note it played, in order, velocity on outlet 1 before
  ///   pitch on outlet 0 (`gKSlider::Emit`). Inlet 1 plays nothing.
  /// - `.nslider`: after **every** message on its one (hot) inlet, the
  ///   accidental on outlet 1, then the pitch on outlet 0 (`CALC`).
  void _emitMusical(int instanceId, int handleId, {int inlet = 0}) {
    final inst = _inst(instanceId);
    final node = inst.nodes[handleId];
    if (node == null || !(node.isKeyboard || node.isStaff)) return;
    void deliver(int outlet, int value) {
      for (final c in [...inst.cables]) {
        if (c.fromHandleId == handleId && c.outlet == outlet) {
          sendInt(instanceId, c.toHandleId, c.inlet, value);
        }
      }
    }

    if (node.isKeyboard) {
      for (final (pitch, velocity) in node.takeNotes()) {
        deliver(1, velocity);
        deliver(0, pitch);
      }
      return;
    }
    if (inlet != 0) return;
    deliver(1, int.parse(node.guiCells[1]));
    deliver(0, int.parse(node.guiCells[0]));
  }

  /// Model what a `.matrixctrl` sent after a message, in order, each list
  /// delivered down every cable from its outlet: `<column> <row> <value>` on
  /// outlet 0 for each changed cell, a row or column on outlet 1 for a query.
  void _emitGrid(int instanceId, int handleId) {
    final inst = _inst(instanceId);
    final node = inst.nodes[handleId];
    if (node == null || !node.isGrid) return;
    for (final (outlet, list) in node.takeGridSends()) {
      for (final c in [...inst.cables]) {
        if (c.fromHandleId == handleId && c.outlet == outlet) {
          sendList(instanceId, c.toHandleId, c.inlet, list);
        }
      }
    }
  }

  /// Model what a `.function` sent after a message, in order, delivered down
  /// every cable from its outlet: a y as a float on outlet 0 (a query or
  /// `nth`), the ramp list on outlet 1 (a bang), a point per list on outlet 2
  /// (`dump`). Edits send nothing (issue #475).
  void _emitFunction(int instanceId, int handleId) {
    final inst = _inst(instanceId);
    final node = inst.nodes[handleId];
    if (node == null || !node.isFunction) return;
    for (final (outlet, send) in node.takeFunctionSends()) {
      for (final c in [...inst.cables]) {
        if (c.fromHandleId != handleId || c.outlet != outlet) continue;
        if (send is double) {
          sendFloat(instanceId, c.toHandleId, c.inlet, send);
        } else {
          sendList(instanceId, c.toHandleId, c.inlet, '$send');
        }
      }
    }
  }

  /// Model a `.nodes`' send (`gNodes::CALC`), after every message on its hot
  /// inlet: the distances on outlet 1 first, then the weights on outlet 0,
  /// each one list delivered down every cable from that outlet (issue #476).
  void _emitNodes(int instanceId, int handleId) {
    final inst = _inst(instanceId);
    final node = inst.nodes[handleId];
    if (node == null || !node.isNodes) return;
    final field = node.liveNodes;
    final (cx, cy) = node.nodesCursor;
    String spell(List<double> values) =>
        [for (final v in values) FakeNode._spell(v)].join(' ');
    final distances = spell(NodesField.distances(field, cx, cy));
    final weights = spell(NodesField.weights(field, cx, cy));
    for (final (outlet, list) in [(1, distances), (0, weights)]) {
      for (final c in [...inst.cables]) {
        if (c.fromHandleId == handleId && c.outlet == outlet) {
          sendList(instanceId, c.toHandleId, c.inlet, list);
        }
      }
    }
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
    // So do the keyboard and the staff: a new `velocity`, or new bounds the
    // held pitch is pulled into at once.
    if (node.isKeyboard || node.isStaff) node.reconfigureMusical();
    // A `.matrixctrl` is re-shaped from its new arguments, every cell cleared
    // (`gMatrixCtrl::ShapeGrid`).
    if (node.isGrid) node.reshapeGrid();
    // A `.function` is rebuilt from its new arguments with an empty store
    // (`gFunction::ShapeStore`).
    if (node.isFunction) node.reshapeFunction();
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
            // What the object holds beyond its arguments, under `state` as
            // libYSE nests it (`DumpState`): a `.function`'s points.
            'state': ?entry.value.dumpState(),
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
      final state = raw['state'];
      if (state is Map) node.restoreState(state);
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
      // The function in; a y, the ramp and the dump out (issue #475).
      case Obj.gFunction:
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
      // The field in; the weights and the distances out (issue #476).
      case Obj.gNodes:
        return const PatcherNodeSnapshot(
          inputs: 1,
          outputs: 2,
          inputKinds: [PatchPortKind.control],
          outputKinds: [PatchPortKind.control, PatchPortKind.control],
        );
      // The grid in; changed cells and a queried line out (issue #474).
      case Obj.gMatrixctrl:
        return const PatcherNodeSnapshot(
          inputs: 1,
          outputs: 2,
          inputKinds: [PatchPortKind.control],
          outputKinds: [PatchPortKind.control, PatchPortKind.control],
        );
      // Pitch and velocity in; pitch and velocity out (issue #473).
      case Obj.gKslider:
        return const PatcherNodeSnapshot(
          inputs: 2,
          outputs: 2,
          inputKinds: [PatchPortKind.control, PatchPortKind.control],
          outputKinds: [PatchPortKind.control, PatchPortKind.control],
        );
      // One hot inlet; pitch and accidental out (issue #473).
      case Obj.gNslider:
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
    if (isKeyboard || isStaff) reconfigureMusical();
    if (isGrid) reshapeGrid();
    if (isNodes) _shapeNodes();
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
  String get guiValue =>
      // An empty `.function` spells its state as the message that empties it.
      isFunction && guiCells.isEmpty ? 'clear' : guiCells.join(' ');
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
    if (isKeyboard) {
      _receiveKeyboardList(inlet, list);
      return;
    }
    if (inlet != 0) return;
    if (isStaff) {
      _receiveStaffList(list);
      return;
    }
    if (isGrid) {
      _receiveGridList(list);
      return;
    }
    if (isFunction) {
      _receiveFunctionList(list);
      return;
    }
    if (isNodes) {
      _receiveNodesList(list);
      return;
    }
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

  // ─── the keyboard and the staff (issue #473) ────────────────────────

  /// Whether this is a `.kslider`: 128 cells, the velocity held on each key.
  bool get isKeyboard => type == Obj.gKslider;

  /// Whether this is a `.nslider`: two cells, a pitch and its accidental.
  bool get isStaff => type == Obj.gNslider;

  /// `.kslider`'s stored velocity — the `velocity` param, or what inlet 1 or a
  /// `<pitch> <velocity>` pair last set.
  int _keyVelocity = 100;

  /// Notes the keyboard has played and not yet sent, `(pitch, velocity)` in
  /// order — drained by the gateway, which sends each down its cables.
  final List<(int, int)> _pendingNotes = [];

  /// The notes played since the last call, in order.
  List<(int, int)> takeNotes() {
    final notes = [..._pendingNotes];
    _pendingNotes.clear();
    return notes;
  }

  /// `.nslider`'s stored pitch (bounded when stored) and chosen accidental (0
  /// for "the default spelling").
  int _staffPitch = 0;
  int _staffAccidental = 0;

  /// The keyboard's or staff's params changed (`setParams`), or it was made.
  void reconfigureMusical() {
    final parts = args.trim().isEmpty
        ? const <String>[]
        : args.trim().split(RegExp(r'\s+'));
    int read(int i, int fallback) => i < parts.length
        ? num.tryParse(parts[i])?.truncate() ?? fallback
        : fallback;
    if (isKeyboard) {
      _keyVelocity = _boundVelocity(read(0, 100));
      return;
    }
    _publishStaff();
  }

  static int _boundVelocity(int v) => v.clamp(0, 127);

  /// `gKSlider::Play`: a pitch on the keyboard takes [velocity] (bounded) and
  /// is sent; one off it is dropped.
  void _play(int pitch, int velocity) {
    if (pitch < 0 || pitch >= 128) return;
    final bounded = _boundVelocity(velocity);
    guiCells = [...guiCells]..[pitch] = '$bounded';
    _pendingNotes.add((pitch, bounded));
  }

  /// A number on the keyboard's [inlet]: inlet 0 plays that pitch at the
  /// stored velocity, inlet 1 stores the velocity and sends nothing.
  void receiveKeyboardNumber(int inlet, double value) {
    final n = value.truncate();
    if (inlet == 0) {
      _play(n, _keyVelocity);
    } else {
      _keyVelocity = _boundVelocity(n);
    }
  }

  /// A bang on the keyboard re-sends every held key, ascending.
  void bangKeyboard() {
    for (var p = 0; p < 128; p++) {
      final v = int.parse(guiCells[p]);
      if (v != 0) _pendingNotes.add((p, v));
    }
  }

  /// `gKSlider::ListIn`.
  void _receiveKeyboardList(int inlet, String list) {
    final tokens = list.trim().split(RegExp(r'\s+'));
    if (tokens.first.isEmpty) return;
    final numbers = [for (final t in tokens) ?num.tryParse(t)];
    if (inlet != 0) {
      if (numbers.isNotEmpty) {
        _keyVelocity = _boundVelocity(numbers[0].truncate());
      }
      return;
    }
    if (tokens.first == 'set') {
      if (numbers.length < 2 || !(numbers[0] >= 0)) return;
      _play(numbers[0].truncate(), numbers[1].truncate());
      return;
    }
    if (tokens.first == 'clear') {
      for (var p = 0; p < 128; p++) {
        if (guiCells[p] == '0') continue;
        guiCells = [...guiCells]..[p] = '0';
        _pendingNotes.add((p, 0));
      }
      return;
    }
    if (numbers.length == 128) {
      // The whole keyboard: only the keys that moved are sent.
      for (var p = 0; p < 128; p++) {
        final wanted = _boundVelocity(numbers[p].truncate());
        if ('$wanted' == guiCells[p]) continue;
        guiCells = [...guiCells]..[p] = '$wanted';
        _pendingNotes.add((p, wanted));
      }
      return;
    }
    if (numbers.length == 1) {
      _play(numbers[0].truncate(), _keyVelocity);
    } else if (numbers.length == 2) {
      _keyVelocity = _boundVelocity(numbers[1].truncate());
      _play(numbers[0].truncate(), _keyVelocity);
    }
  }

  /// `gNSlider`'s bounds: `minimum maximum`, sorted and kept inside MIDI.
  int _boundPitch(int value) {
    final parts = args.trim().isEmpty
        ? const <String>[]
        : args.trim().split(RegExp(r'\s+'));
    int read(int i, int fallback) => i < parts.length
        ? num.tryParse(parts[i])?.truncate() ?? fallback
        : fallback;
    final a = read(0, 0).clamp(0, 127);
    final b = read(1, 127).clamp(0, 127);
    return value.clamp(a < b ? a : b, a < b ? b : a);
  }

  int get _staffSpelling {
    final parts = args.trim().isEmpty
        ? const <String>[]
        : args.trim().split(RegExp(r'\s+'));
    return parts.length > 2 ? num.tryParse(parts[2])?.truncate() ?? 1 : 1;
  }

  /// Re-render the staff's two cells (`gNSlider::Pitch` / `Accidental`).
  void _publishStaff() {
    final pitch = _boundPitch(_staffPitch);
    const black = {1, 3, 6, 8, 10};
    final accidental = !black.contains(pitch % 12)
        ? 0
        : _staffAccidental > 0
        ? 1
        : _staffAccidental < 0
        ? -1
        : (_staffSpelling < 0 ? -1 : 1);
    guiCells = ['$pitch', '$accidental'];
  }

  /// A number on the staff: the pitch, spelled the default way.
  void receiveStaffNumber(int inlet, double value) {
    if (inlet != 0) return;
    _staffPitch = _boundPitch(value.truncate());
    _staffAccidental = 0;
    _publishStaff();
  }

  /// `gNSlider::ListIn`: `set 0 <pitch>`, `set 1 <accidental>`, or
  /// `<pitch> [<accidental>]`.
  void _receiveStaffList(String list) {
    final tokens = list.trim().split(RegExp(r'\s+'));
    if (tokens.first == 'set') {
      final numbers = [for (final t in tokens.skip(1)) num.tryParse(t)];
      if (numbers.length < 2 || numbers[0] == null || numbers[1] == null) {
        return;
      }
      final index = numbers[0]!;
      if (!(index >= 0) || index >= 2) return;
      if (index.truncate() == 0) {
        _staffPitch = _boundPitch(numbers[1]!.truncate());
      } else {
        _staffAccidental = numbers[1]!.truncate();
      }
      _publishStaff();
      return;
    }
    final numbers = <num>[];
    for (final t in tokens.take(2)) {
      final n = num.tryParse(t);
      if (n == null) break;
      numbers.add(n);
    }
    if (numbers.isEmpty) return;
    _staffAccidental = numbers.length >= 2 ? numbers[1].truncate() : 0;
    _staffPitch = _boundPitch(numbers[0].truncate());
    _publishStaff();
  }

  // ─── the grid (issue #474) ──────────────────────────────────────────

  /// Whether this is a `.matrixctrl`: one cell per grid cell, column-major.
  bool get isGrid => type == Obj.gMatrixctrl;

  /// The grid's shape and range, from its creation arguments.
  MatrixctrlArgs get gridArgs => MatrixctrlArgs.parse(args);

  /// Each cell as stored — bounded on the way in and again on the way out, as
  /// `gMatrixCtrl` does (cells start at 0, which a range above 0 reports as
  /// its minimum).
  List<double> _grid = const [];

  /// Lists the grid has sent and the gateway has not yet delivered, as
  /// (outlet, list), in order.
  final List<(int, String)> _gridSends = [];

  /// The grid's sends since the last call, in order.
  List<(int, String)> takeGridSends() {
    final sends = [..._gridSends];
    _gridSends.clear();
    return sends;
  }

  /// `gMatrixCtrl::ShapeGrid`: a fresh grid of the arguments' shape, every
  /// cell 0.
  void reshapeGrid() {
    _grid = List.filled(gridArgs.cellCount, 0);
    _publishGrid();
  }

  void _publishGrid() {
    final range = gridArgs.range;
    guiCells = [for (final v in _grid) _spell(_bound(v, range))];
  }

  /// `SendCell`: the triple for the cell at [index].
  void _sendCell(int index) {
    final grid = gridArgs;
    _gridSends.add((
      0,
      '${grid.columnOf(index)} ${grid.rowOf(index)} ${guiCells[index]}',
    ));
  }

  /// `SendAll`: every cell, column by column.
  void sendWholeGrid() {
    for (var i = 0; i < _grid.length; i++) {
      _sendCell(i);
    }
  }

  /// `gMatrixCtrl::ListIn`: `set <index> <value>`, `clear`, `getrow <row>`,
  /// `getcolumn <column>`, a list of every cell, or `<column> <row> <value>`.
  /// Non-numeric tokens are skipped when counting numbers, as the engine's
  /// parser skips them.
  void _receiveGridList(String list) {
    final tokens = list.trim().split(RegExp(r'\s+'));
    if (tokens.first.isEmpty) return;
    final grid = gridArgs;
    final range = grid.range;
    int whole(double n) =>
        n.isFinite && n.abs() < 2147483648 ? n.truncate() : 0;
    final keyword = tokens.first;
    final numbers = [for (final t in tokens) ?double.tryParse(t)];
    if (keyword == 'set') {
      if (numbers.length < 2 || !(numbers[0] >= 0)) return;
      final at = whole(numbers[0]);
      if (at >= _grid.length) return;
      _grid[at] = _bound(numbers[1], range);
      _publishGrid();
      _sendCell(at);
      return;
    }
    if (keyword == 'clear') {
      _grid = List.filled(_grid.length, 0);
      _publishGrid();
      sendWholeGrid();
      return;
    }
    if (keyword == 'getrow' || keyword == 'getcolumn') {
      final column = keyword == 'getcolumn';
      if (numbers.isEmpty || !(numbers[0] >= 0)) return;
      final at = whole(numbers[0]);
      if (at >= (column ? grid.columns : grid.rows)) return;
      final count = column ? grid.rows : grid.columns;
      _gridSends.add((
        1,
        [
          for (var i = 0; i < count; i++)
            guiCells[column ? grid.indexOf(at, i) : grid.indexOf(i, at)],
        ].join(' '),
      ));
      return;
    }
    if (numbers.length == _grid.length) {
      for (var i = 0; i < _grid.length; i++) {
        _grid[i] = _bound(numbers[i], range);
      }
      _publishGrid();
      sendWholeGrid();
      return;
    }
    if (numbers.length != 3) return;
    if (!(numbers[0] >= 0) || !(numbers[1] >= 0)) return;
    final column = whole(numbers[0]);
    final row = whole(numbers[1]);
    if (column >= grid.columns || row >= grid.rows) return;
    final at = grid.indexOf(column, row);
    _grid[at] = _bound(numbers[2], range);
    _publishGrid();
    _sendCell(at);
  }

  // ─── the breakpoint function (issue #475) ───────────────────────────

  /// Whether this is a `.function`: one `<x> <y> <curve>` cell per point.
  bool get isFunction => type == Obj.gFunction;

  /// The function's capacity and y range, from its creation arguments.
  FunctionArgs get functionArgs => FunctionArgs.parse(args);

  /// The points as stored, ascending by x — bounded on the way in, as
  /// `gFunction::StorePoint` keeps them.
  final List<(double, double, double)> _function = [];

  /// What the function has sent and the gateway has not yet delivered, as
  /// (outlet, value): a double for outlet 0's float, a list string otherwise.
  final List<(int, Object)> _functionSends = [];

  /// The function's sends since the last call, in order.
  List<(int, Object)> takeFunctionSends() {
    final sends = [..._functionSends];
    _functionSends.clear();
    return sends;
  }

  /// `ShapeStore`: an empty store for the new arguments.
  void reshapeFunction() {
    _function.clear();
    _publishFunction();
  }

  void _publishFunction() {
    guiCells = [
      for (final (x, y, c) in _function)
        '${_spell(x)} ${_spell(y)} ${_spell(c)}',
    ];
  }

  /// `BoundCurve`: into [-1, 1], a NaN read as 0.
  static double _boundCurve(double c) {
    if (c.isNaN) return 0;
    return c.clamp(-1.0, 1.0);
  }

  /// `StorePoint`: replace the point at exactly [x], or insert in order.
  /// Refused when the store is full. [x] is already sanitised.
  void _storePoint(double x, double y, double curve) {
    var at = 0;
    while (at < _function.length && _function[at].$1 < x) {
      at++;
    }
    final point = (x, _bound(y, functionArgs.range), curve);
    if (at < _function.length && _function[at].$1 == x) {
      _function[at] = point;
      return;
    }
    if (_function.length >= functionArgs.capacity) return;
    _function.insert(at, point);
  }

  /// `SanitizeX`: a negative x folds onto 0, a NaN is refused (null).
  static double? _sanitizeX(double x) {
    if (x.isNaN) return null;
    return x < 0 ? 0 : x;
  }

  /// `Query`: the curved y between the points either side of [x], or the
  /// nearest end's y outside them; nothing for an empty function.
  void queryFunction(double x) {
    if (x.isNaN || _function.isEmpty) return;
    double y;
    if (x <= _function.first.$1) {
      y = _function.first.$2;
    } else if (x >= _function.last.$1) {
      y = _function.last.$2;
    } else {
      var hi = 0;
      while (_function[hi].$1 < x) {
        hi++;
      }
      final (lx, ly, _) = _function[hi - 1];
      final (rx, ry, rc) = _function[hi];
      y = ly + FunctionPoint.shape((x - lx) / (rx - lx), rc) * (ry - ly);
    }
    _functionSends.add((0, y));
  }

  /// `EmitRamp`: `<y> <time>` per point, the first time 0 and each later one
  /// the distance in x from the point before, out outlet 1.
  void sendRamp() {
    if (_function.isEmpty) return;
    final parts = <String>[];
    for (var i = 0; i < _function.length; i++) {
      final delta = i == 0 ? 0.0 : _function[i].$1 - _function[i - 1].$1;
      parts
        ..add(_spell(_function[i].$2))
        ..add(_spell(delta));
    }
    _functionSends.add((1, parts.join(' ')));
  }

  /// `gFunction::ListIn`: `set`, `setcurve`, `nth`, `clear`, `dump`, then
  /// two numbers as a new point or 3N as the whole state. Edits send nothing.
  void _receiveFunctionList(String list) {
    final tokens = list.trim().split(RegExp(r'\s+'));
    if (tokens.first.isEmpty) return;
    final keyword = tokens.first;
    final args = [for (final t in tokens.skip(1)) ?double.tryParse(t)];
    int? index(double n) => n >= 0 ? n.truncate() : null;
    switch (keyword) {
      case 'set':
        if (args.length < 3) return;
        final at = index(args[0]);
        final x = _sanitizeX(args[1]);
        if (at == null || x == null || at >= _function.length) return;
        final curve = args.length > 3 ? _boundCurve(args[3]) : _function[at].$3;
        _function.removeAt(at);
        _storePoint(x, args[2], curve);
        _publishFunction();
        return;
      case 'setcurve':
        if (args.length < 2) return;
        final at = index(args[0]);
        if (at == null || at >= _function.length) return;
        final (x, y, _) = _function[at];
        _function[at] = (x, y, _boundCurve(args[1]));
        _publishFunction();
        return;
      case 'nth':
        if (args.isEmpty) return;
        final at = index(args[0]);
        if (at == null || at >= _function.length) return;
        _functionSends.add((0, _function[at].$2));
        return;
      case 'clear':
        if (args.isEmpty) {
          _function.clear();
        } else {
          final at = index(args[0]);
          if (at == null || at >= _function.length) return;
          _function.removeAt(at);
        }
        _publishFunction();
        return;
      case 'dump':
        for (var i = 0; i < _function.length; i++) {
          final (x, y, c) = _function[i];
          _functionSends.add((2, '$i ${_spell(x)} ${_spell(y)} ${_spell(c)}'));
        }
        return;
    }
    final numbers = [for (final t in tokens) ?double.tryParse(t)];
    if (numbers.length == 2) {
      final x = _sanitizeX(numbers[0]);
      if (x == null) return;
      _storePoint(x, numbers[1], 0);
      _publishFunction();
      return;
    }
    if (numbers.length >= 3 && numbers.length % 3 == 0) {
      _function.clear();
      for (var i = 0; i < numbers.length; i += 3) {
        final x = _sanitizeX(numbers[i]);
        if (x == null) continue;
        _storePoint(x, numbers[i + 1], _boundCurve(numbers[i + 2]));
      }
      _publishFunction();
    }
  }

  /// What the object saves beyond its arguments (`DumpState`), or null when
  /// it holds nothing: a `.function`'s points.
  Map<String, Object?>? dumpState() {
    if (!isFunction || _function.isEmpty) return null;
    return {
      'points': [
        for (final (x, y, c) in _function) {'x': x, 'y': y, 'curve': c},
      ],
    };
  }

  /// `RestoreState`: refill through the same sorted, bounded store.
  void restoreState(Map<Object?, Object?> state) {
    if (!isFunction) return;
    _function.clear();
    final points = state['points'];
    if (points is List) {
      for (final p in points) {
        if (p is! Map) continue;
        double read(String key) => (p[key] as num?)?.toDouble() ?? 0;
        final x = _sanitizeX(read('x'));
        if (x == null) continue;
        _storePoint(x, read('y'), _boundCurve(read('curve')));
      }
    }
    _publishFunction();
  }

  // ─── the interpolation field (issue #476) ────────────────────────────

  /// Whether this is a `.nodes`: one `<x> <y> <radius>` cell per node.
  bool get isNodes => type == Obj.gNodes;

  /// Every node bank slot, `MAX_NODES` of them, allocated once: the count
  /// only decides how many are live, so a grown field reveals what a shrunk
  /// one hid (`gNodes`' bound-not-capacity rule).
  final List<FieldNode> _nodeBank = List.filled(
    NodesArgs.maxCount,
    const FieldNode(0, 0, NodesArgs.defaultRadius),
  );
  int _nodeCount = NodesArgs.defaultCount;

  /// The cursor, as the last two-number list put it.
  (double, double) nodesCursor = (0, 0);

  /// The live nodes, in node order.
  List<FieldNode> get liveNodes => _nodeBank.sublist(0, _nodeCount);

  /// The count from the creation argument. The field itself is not saved
  /// (no `DumpState`), so a reload is that many unit nodes at the origin.
  void _shapeNodes() {
    _nodeCount = NodesArgs.parse(args).count;
    _publishNodes();
  }

  void _publishNodes() {
    guiCells = [
      for (final n in liveNodes)
        '${_spell(n.x)} ${_spell(n.y)} ${_spell(n.radius)}',
    ];
  }

  /// `gNodes::ListIn`: `set <i> <x> <y> [<radius>]` moves one node, two
  /// numbers are the cursor, three or more the whole field as triples (a
  /// trailing partial one ignored). Tokens that are not numbers are skipped.
  /// The send that follows is the gateway's ([FakePatcherGateway._emitNodes]).
  void _receiveNodesList(String list) {
    final tokens = list.trim().split(RegExp(r'\s+'));
    if (tokens.first.isEmpty) return;
    if (tokens.first == 'set') {
      final args = [for (final t in tokens.skip(1)) ?double.tryParse(t)];
      if (args.length < 3) return;
      if (!(args[0] >= 0)) return;
      final at = args[0].truncate();
      if (at >= _nodeCount) return;
      final radius = args.length > 3 ? args[3] : _nodeBank[at].radius;
      _nodeBank[at] = FieldNode(args[1], args[2], radius);
      _publishNodes();
      return;
    }
    final numbers = [for (final t in tokens) ?double.tryParse(t)];
    if (numbers.length < 2) return;
    if (numbers.length == 2) {
      nodesCursor = (numbers[0], numbers[1]);
      return;
    }
    var written = 0;
    for (
      var i = 0;
      i + 2 < numbers.length && written < NodesArgs.maxCount;
      i += 3
    ) {
      _nodeBank[written++] = FieldNode(
        numbers[i],
        numbers[i + 1],
        numbers[i + 2],
      );
    }
    _nodeCount = written;
    _publishNodes();
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
      // A fresh `.function` holds no points, so it has no cells.
      case Obj.gFunction:
        return const [];
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
