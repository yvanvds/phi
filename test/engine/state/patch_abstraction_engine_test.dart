import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:phi/engine/state/patch_library_controller.dart';
import 'package:phi/engine/state/patch_reconciler.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:yse/yse.dart';

/// Abstractions against the real engine (issue #553): what the editor believes
/// about an instance is what libYSE holds, read back from the native graph and
/// from a dump, not from the editor's own mirror. Nothing here is mounted, so no
/// test disposes a mounted patcher (the #548 teardown deadlock).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EntityAddress patch(String name) =>
      EntityAddress(kind: RegistryKinds.patch, segments: [name]);

  late RealPatcherGateway gateway;
  late ProjectRegistry registry;
  late PatchReconciler reconciler;
  late PatchLibraryController library;
  var engineUp = false;

  setUpAll(() {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
    engineUp = true;
  });

  tearDownAll(() {
    if (engineUp) System.instance.close();
  });

  setUp(() {
    gateway = RealPatcherGateway();
    registry = ProjectRegistry();
    reconciler = PatchReconciler(
      gateway: gateway,
      resolveBus: (_) => null,
      onNotice: (_) {},
    );
    library = PatchLibraryController(
      registry: registry,
      patches: reconciler,
      gateway: gateway,
      busOptions: () => const [],
    );
  });

  tearDown(() {
    library.dispose();
    reconciler.teardown();
    gateway.disposeAll();
  });

  PatcherController newPatch(String name) {
    registry.createEntity(patch(name), payload: PatchPayload.empty.toJson());
    reconciler.sync(registry);
    return library.editorFor(patch(name))!;
  }

  PatchNodeId make(
    PatcherController editor,
    String type, {
    String args = '',
    Offset at = Offset.zero,
  }) {
    final desc = editor.objectTypes().firstWhere((d) => d.type == type);
    return editor.createObject(desc: desc, position: at, args: args)!;
  }

  PatchPortId inlet(PatchNodeId id) =>
      PatchPortId(nodeId: id, side: PatchPortSide.input, index: 0);
  PatchPortId outlet(PatchNodeId id) =>
      PatchPortId(nodeId: id, side: PatchPortSide.output, index: 0);

  /// `~inlet 0` → `~* 0.5` → `~outlet 0`.
  (PatcherController, PatchNodeId) gain() {
    final editor = newPatch('gain');
    final i = make(editor, Obj.dInlet, args: '0');
    final g = make(editor, Obj.dMultiply, args: '0.5', at: const Offset(0, 80));
    final o = make(editor, Obj.dOutlet, args: '0', at: const Offset(0, 160));
    editor
      ..connectViaGesture(outlet(i), inlet(g))
      ..connectViaGesture(outlet(g), inlet(o));
    return (editor, g);
  }

  test('the engine holds an instance as a box named by the address', () {
    gain();
    final parent = newPatch('song');

    final box = make(parent, Obj.patcher, args: 'patch.gain');

    final native = gateway.enumerate(parent.instanceId);
    final nativeBox = native.objects.singleWhere((o) => o.type == Obj.patcher);
    expect(
      nativeBox.args,
      'patch.gain',
      reason: 'the name survives the engine',
    );
    expect(nativeBox.ports.inputs, 1);
    expect(nativeBox.ports.outputs, 1);
    expect(
      native.objects.where((o) => o.container == nativeBox.handleId),
      hasLength(3),
    );
    expect(native.connections, hasLength(2));
    expect(parent.abstractionOf(box), patch('gain'));
  });

  test('a change to the definition lands on the native copy in place', () {
    final (definition, multiply) = gain();
    final parent = newPatch('song');
    make(parent, Obj.patcher, args: 'patch.gain');
    final handleOf = gateway
        .enumerate(parent.instanceId)
        .objects
        .singleWhere((o) => o.type == Obj.dMultiply)
        .handleId;

    definition.applyParams(multiply, '0.25');

    final copy = gateway
        .enumerate(parent.instanceId)
        .objects
        .singleWhere((o) => o.type == Obj.dMultiply);
    expect(copy.args, '0.25');
    expect(copy.handleId, handleOf, reason: 'the same object, not a new one');
  });

  test('a parent\'s cable survives on the pin, in the native graph', () {
    final (definition, multiply) = gain();
    final parent = newPatch('song');
    final box = make(parent, Obj.patcher, args: 'patch.gain');
    final sine = make(parent, Obj.dSine, args: '440');
    expect(parent.connectViaGesture(outlet(sine), inlet(box)), isTrue);

    definition.applyParams(multiply, '0.25');

    final native = gateway.enumerate(parent.instanceId);
    final inletHandle = native.objects
        .singleWhere((o) => o.type == Obj.dInlet)
        .handleId;
    expect(
      native.connections.where((c) => c.toHandleId == inletHandle),
      hasLength(1),
    );
  });

  test('a saved parent parses back to an instance that still follows', () {
    final (definition, multiply) = gain();
    final parent = newPatch('song');
    make(parent, Obj.patcher, args: 'patch.gain');
    reconciler.flushToPayloads(registry, null);

    final payload = PatchPayload.fromJson(
      (registry.entityAt(patch('song'))!.payload as Map)
          .cast<String, Object?>(),
    );
    final reloadedId = gateway.createInstance(name: 'reloaded');
    gateway.parseJson(reloadedId, jsonEncode(payload.dump));
    final reloaded = PatcherController.bound(gateway, instanceId: reloadedId)
      ..rebuildFromInstance();
    addTearDown(reloaded.dispose);

    final box = reloaded
        .nodesIn(null)
        .singleWhere((n) => n.type == Obj.patcher);
    expect(reloaded.abstractionOf(box.id), patch('gain'));
    expect(reloaded.nodesIn(box.id), hasLength(3));
    expect(reloaded.graph.cables, hasLength(2));

    // The live project keeps following through the same machinery.
    definition.applyParams(multiply, '0.125');
    final live = parent.nodesIn(
      parent.nodesIn(null).singleWhere((n) => n.type == Obj.patcher).id,
    );
    expect(
      parent.argsOf(live.firstWhere((n) => n.type == Obj.dMultiply).id),
      '0.125',
    );
  });

  group('#0 (issue #561)', () {
    Future<void> flush() => Future<void>.delayed(Duration.zero);

    /// `.s ping#0` beside `.r ping#0` → `.s pong#0`: a value sent to `ping`
    /// comes out on `pong`, only if the `.r` hears that `.s`.
    ///
    /// Both `.s` are bus-only (their second argument), which delivers without a
    /// rendered block: the in-patcher path drains on the audio thread, so it
    /// would need a mounted patch, and a mounted patch here would have to be
    /// disposed (#548). The integration test covers that path.
    PatcherController echo() {
      final editor = newPatch('echo');
      make(editor, Obj.gSend, args: 'ping#0 1');
      final r = make(editor, Obj.gReceive, args: 'ping#0');
      final s = make(editor, Obj.gSend, args: 'pong#0 1');
      editor.connectViaGesture(outlet(r), inlet(s));
      return editor;
    }

    int sendTo(PatcherController parent, String name) => gateway
        .enumerate(parent.instanceId)
        .objects
        .singleWhere((o) => o.type == Obj.gSend && o.args == name)
        .handleId;

    Future<List<BusValue>> heardAt(String address) async {
      final heard = <BusValue>[];
      final subscription = Bus.subscribe(address).listen((f) {
        heard.add(f.value);
      });
      addTearDown(subscription.cancel);
      await flush();
      return heard;
    }

    test('the engine keeps two instances\' names apart', () async {
      echo();
      final parent = newPatch('song');
      final one = make(parent, Obj.patcher, args: 'patch.echo');
      final two = make(parent, Obj.patcher, args: 'patch.echo');
      final a = parent.instanceNumberOf(one)!;
      final b = parent.instanceNumberOf(two)!;
      expect(a, isNot(b));

      final atA = await heardAt('patcher.song.pong#$a');
      final atB = await heardAt('patcher.song.pong#$b');

      gateway.sendFloat(
        parent.instanceId,
        sendTo(parent, 'ping#$a 1'),
        0,
        0.25,
      );
      await flush();
      expect(atA, [const BusFloat(0.25)], reason: 'its own .r heard it');
      expect(atB, isEmpty, reason: 'the other instance did not');

      gateway.sendFloat(parent.instanceId, sendTo(parent, 'ping#$b 1'), 0, 0.5);
      await flush();
      expect(atA, hasLength(1));
      expect(atB, [const BusFloat(0.5)]);
    });

    test('a name stays where it is when the definition changes around it', () {
      final definition = echo();
      final parent = newPatch('song');
      final box = make(parent, Obj.patcher, args: 'patch.echo');
      final number = parent.instanceNumberOf(box)!;
      final handle = sendTo(parent, 'pong#$number 1');
      final cables = gateway.enumerate(parent.instanceId).connections;
      expect(cables, hasLength(1));

      make(definition, Obj.dSine, args: '440', at: const Offset(0, 200));

      expect(sendTo(parent, 'pong#$number 1'), handle, reason: 'not recreated');
      expect(gateway.enumerate(parent.instanceId).connections, hasLength(1));
    });

    test('a duplicate is spelled apart in the engine, wires intact', () async {
      echo();
      final parent = newPatch('song');
      final box = make(parent, Obj.patcher, args: 'patch.echo');
      parent.selectNodes({box});
      parent.duplicateSelection();
      final copy = parent.nodesIn(null).singleWhere((n) => n.id != box).id;
      final a = parent.instanceNumberOf(box)!;
      final b = parent.instanceNumberOf(copy)!;
      expect(a, isNot(b));

      final atA = await heardAt('patcher.song.pong#$a');
      final atB = await heardAt('patcher.song.pong#$b');
      gateway.sendFloat(
        parent.instanceId,
        sendTo(parent, 'ping#$b 1'),
        0,
        0.75,
      );
      await flush();

      expect(atB, [const BusFloat(0.75)]);
      expect(atA, isEmpty);
    });

    test('a saved number parses back, and the copies read the same', () {
      echo();
      final parent = newPatch('song');
      final box = make(parent, Obj.patcher, args: 'patch.echo');
      final number = parent.instanceNumberOf(box)!;
      reconciler.flushToPayloads(registry, null);

      final payload = PatchPayload.fromJson(
        (registry.entityAt(patch('song'))!.payload as Map)
            .cast<String, Object?>(),
      );
      final reloadedId = gateway.createInstance(name: 'reloaded');
      gateway.parseJson(reloadedId, jsonEncode(payload.dump));
      final reloaded = PatcherController.bound(gateway, instanceId: reloadedId)
        ..rebuildFromInstance();
      addTearDown(reloaded.dispose);

      final again = reloaded
          .nodesIn(null)
          .singleWhere((n) => n.type == Obj.patcher);
      expect(reloaded.instanceNumberOf(again.id), number);
      expect(
        reloaded.nodesIn(again.id).map((n) => reloaded.argsOf(n.id)),
        containsAll(['ping#$number 1', 'ping#$number', 'pong#$number 1']),
      );
    });
  });
}
