import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:yse/yse.dart';

import '../test_doubles/fake_patcher_gateway.dart';

/// Contract tests for the multi-instance [PatcherGateway] behaviour (issue
/// #219), exercised against [FakePatcherGateway] — the CI-runnable model of
/// the gateway (the real one needs `libyse.dll`, verified by hand). The two
/// "Done when" guarantees are covered: instance isolation (ops on one
/// instance never leak to another) and source re-mounting.
void main() {
  late FakePatcherGateway gateway;

  setUp(() => gateway = FakePatcherGateway());

  group('instance lifecycle + isolation', () {
    test('createInstance hands out distinct ids', () {
      final a = gateway.createInstance(mainOutputs: 1);
      final b = gateway.createInstance(mainOutputs: 2);
      expect(a, isNot(b));
      expect(gateway.instances.keys, containsAll(<int>[a, b]));
    });

    test('objects created on one instance never appear on another', () {
      final a = gateway.createInstance();
      final b = gateway.createInstance();

      final sineA = gateway.createObject(a, Obj.dSine, args: '440');
      final dacA = gateway.createObject(a, Obj.dDac);
      final sineB = gateway.createObject(b, Obj.dSine, args: '220');

      expect(gateway.instances[a]!.nodes.keys, containsAll(<int>[sineA, dacA]));
      expect(gateway.instances[a]!.nodes.containsKey(sineB), isFalse);
      expect(gateway.instances[b]!.nodes.keys, equals(<int>[sineB]));
      expect(gateway.instances[b]!.nodes.containsKey(sineA), isFalse);
    });

    test('cables and deletes stay within their instance', () {
      final a = gateway.createInstance();
      final b = gateway.createInstance();
      final s1 = gateway.createObject(a, Obj.gSlider);
      final s2 = gateway.createObject(a, Obj.dSine);
      gateway.createObject(b, Obj.dSine);

      gateway.connect(a, fromHandleId: s1, outlet: 0, toHandleId: s2, inlet: 0);

      expect(gateway.instances[a]!.cables, hasLength(1));
      expect(gateway.instances[b]!.cables, isEmpty);

      // Deleting the *same* handle id on the wrong instance is a no-op there.
      gateway.deleteObject(b, s2);
      expect(gateway.instances[a]!.nodes.containsKey(s2), isTrue);

      gateway.deleteObject(a, s2);
      expect(gateway.instances[a]!.nodes.containsKey(s2), isFalse);
      // Deleting the node drops the cable touching it.
      expect(gateway.instances[a]!.cables, isEmpty);
    });

    test('disposeInstance drops only that instance', () {
      final a = gateway.createInstance();
      final b = gateway.createInstance();
      gateway.createObject(a, Obj.dSine);
      gateway.createObject(b, Obj.dSine);

      gateway.disposeInstance(a);

      expect(gateway.instances.containsKey(a), isFalse);
      expect(gateway.instances.containsKey(b), isTrue);
    });

    test('disposeAll clears every instance', () {
      gateway.createInstance();
      gateway.createInstance();
      gateway.disposeAll();
      expect(gateway.instances, isEmpty);
    });

    test('positions and control values are keyed per instance', () {
      final a = gateway.createInstance();
      final b = gateway.createInstance();
      final na = gateway.createObject(a, Obj.gSlider);
      final nb = gateway.createObject(b, Obj.gSlider);

      gateway.setNodePosition(a, na, const Offset(10, 20));
      gateway.sendFloat(a, na, 0, 0.5);

      expect(gateway.getNodePosition(a, na), const Offset(10, 20));
      expect(gateway.getNodePosition(b, nb), isNull);
      expect(gateway.instances[a]!.nodes[na]!.lastValueByInlet[0], 0.5);
      expect(gateway.instances[b]!.nodes[nb]!.lastValueByInlet, isEmpty);
    });
  });

  group('source re-mounting', () {
    test(
      'mountAsSource records the bus; re-mount follows a placement change',
      () {
        final a = gateway.createInstance();

        gateway.mountAsSource(a);
        expect(gateway.instances[a]!.mounted, isTrue);
        expect(gateway.instances[a]!.mountedBus, isNull); // master

        gateway.mountAsSource(a, busChannelId: 7);
        expect(gateway.instances[a]!.mounted, isTrue);
        expect(gateway.instances[a]!.mountedBus, 7);

        gateway.unmountSource(a);
        expect(gateway.instances[a]!.mounted, isFalse);
        expect(gateway.instances[a]!.mountedBus, isNull);
      },
    );

    test('mounting one instance does not mount another', () {
      final a = gateway.createInstance();
      final b = gateway.createInstance();

      gateway.mountAsSource(a, busChannelId: 3);

      expect(gateway.instances[a]!.mounted, isTrue);
      expect(gateway.instances[b]!.mounted, isFalse);
    });
  });

  group('pass* control API is per-instance', () {
    test('a receiver in one instance is not addressable from another', () {
      final a = gateway.createInstance();
      final b = gateway.createInstance();
      gateway.createObject(a, Obj.gReceive, args: 'cutoff');

      expect(gateway.passFloat(a, 0.4, 'cutoff'), isTrue);
      expect(gateway.passBang(a, 'cutoff'), isTrue);
      // Instance b has no such receiver.
      expect(gateway.passFloat(b, 0.4, 'cutoff'), isFalse);
      // An unknown name in a is still false.
      expect(gateway.passInt(a, 1, 'unknown'), isFalse);
    });
  });

  group('metadata passthrough', () {
    test('objectTypes filters out the subpatcher type', () {
      final types = gateway.objectTypes().map((d) => d.type);
      expect(types, isNot(contains(Obj.patcher)));
      expect(types, contains(Obj.dSine));
    });

    test(
      'descriptors carry categories, docs, accepts, out types and params',
      () {
        final sine = gateway.objectTypes().firstWhere(
          (d) => d.type == Obj.dSine,
        );

        expect(sine.category, PatchObjectCategory.oscillator);
        expect(sine.isDsp, isTrue);
        expect(sine.description, isNotEmpty);

        final freq = sine.inlets.single;
        expect(freq.accepts, contains(PatchInletAccept.buffer));
        expect(freq.isDspInput, isTrue); // accepts a buffer → audio inlet

        expect(sine.outlets.single.type, PatchOutletType.buffer);
        expect(sine.params.single.defaultValue, '440');
      },
    );

    test('a custom catalogue is honoured, still minus the subpatcher', () {
      gateway.objectTypesCatalogue = const [
        PatchObjectDescriptor(
          type: Obj.patcher,
          description: 'subpatch',
          category: PatchObjectCategory.generic,
          isDsp: false,
          inlets: [],
          outlets: [],
          params: [],
        ),
        PatchObjectDescriptor(
          type: Obj.dSaw,
          description: 'sawtooth',
          category: PatchObjectCategory.oscillator,
          isDsp: true,
          inlets: [],
          outlets: [],
          params: [],
        ),
      ];

      final types = gateway.objectTypes().map((d) => d.type).toList();
      expect(types, <String>[Obj.dSaw]);
    });
  });

  group('sendBang', () {
    test('records the banged inlet on the target node', () {
      final a = gateway.createInstance();
      final button = gateway.createObject(a, Obj.gButton);

      gateway.sendBang(a, button, 0);

      expect(gateway.instances[a]!.nodes[button]!.bangedInlets, <int>[0]);
    });
  });

  group('enumerate (graph read-back for canvas rebuild, issue #308)', () {
    test('returns every object with its type, args, position and ports', () {
      final a = gateway.createInstance();
      final sine = gateway.createObject(a, Obj.dSine, args: '440');
      final dac = gateway.createObject(a, Obj.dDac);
      gateway.setNodePosition(a, sine, const Offset(40, 60));

      final snapshot = gateway.enumerate(a);

      expect(snapshot.objects, hasLength(2));
      final sineObj = snapshot.objects.firstWhere((o) => o.handleId == sine);
      expect(sineObj.type, Obj.dSine);
      expect(sineObj.args, '440');
      expect(sineObj.position, const Offset(40, 60));
      // Ports come back exactly as inspect reports them.
      expect(sineObj.ports.inputs, 1);
      expect(sineObj.ports.outputs, 1);
      expect(sineObj.ports.outputKinds.single, PatchPortKind.audio);
      // An object whose position was never set reports null.
      final dacObj = snapshot.objects.firstWhere((o) => o.handleId == dac);
      expect(dacObj.position, isNull);
    });

    test('returns every connection in native handle-id terms', () {
      final a = gateway.createInstance();
      final sine = gateway.createObject(a, Obj.dSine);
      final dac = gateway.createObject(a, Obj.dDac);
      gateway.connect(
        a,
        fromHandleId: sine,
        outlet: 0,
        toHandleId: dac,
        inlet: 0,
      );

      final connections = gateway.enumerate(a).connections;

      expect(connections, hasLength(1));
      final c = connections.single;
      expect(c.fromHandleId, sine);
      expect(c.outlet, 0);
      expect(c.toHandleId, dac);
      expect(c.inlet, 0);
    });

    test('an empty instance enumerates to nothing', () {
      final a = gateway.createInstance();
      final snapshot = gateway.enumerate(a);
      expect(snapshot.objects, isEmpty);
      expect(snapshot.connections, isEmpty);
    });

    test('enumeration is scoped to its own instance', () {
      final a = gateway.createInstance();
      final b = gateway.createInstance();
      gateway.createObject(a, Obj.dSine);

      expect(gateway.enumerate(a).objects, hasLength(1));
      expect(gateway.enumerate(b).objects, isEmpty);
    });
  });

  group('dumpJson / parseJson round-trip (structured, re-parseable)', () {
    test('a dumped graph re-parses into an identical enumeration', () {
      final a = gateway.createInstance();
      final sine = gateway.createObject(a, Obj.dSine, args: '440');
      final dac = gateway.createObject(a, Obj.dDac);
      gateway.setNodePosition(a, sine, const Offset(40, 60));
      gateway.connect(
        a,
        fromHandleId: sine,
        outlet: 0,
        toHandleId: dac,
        inlet: 0,
      );
      final dump = gateway.dumpJson(a);

      // Parse the dump into a fresh instance and compare its enumeration.
      final b = gateway.createInstance();
      gateway.parseJson(b, dump);

      final objects = gateway.enumerate(b).objects;
      expect(objects, hasLength(2));
      final sineObj = objects.firstWhere((o) => o.type == Obj.dSine);
      expect(sineObj.args, '440');
      expect(sineObj.position, const Offset(40, 60));
      expect(gateway.enumerate(b).connections, hasLength(1));
    });

    test('parseJson tolerates an opaque (non-list-objects) dump', () {
      final a = gateway.createInstance();
      gateway.createObject(a, Obj.dSine);
      // A hand-written placeholder dump (objects is a count, not a list) leaves
      // the instance untouched rather than throwing.
      gateway.parseJson(a, '{"objects":2,"cables":1}');
      expect(gateway.enumerate(a).objects, hasLength(1));
    });
  });

  group('engine-direct bus addressing (issue #318)', () {
    test('a named instance registers under its bus name and receives a '
        'publish to patcher.<name>.<slot>', () {
      final a = gateway.createInstance(name: 'fx.swirl');

      expect(gateway.instances[a]!.busName, 'fx.swirl');
      // A publish to the instance's bus address lands on it at the given slot.
      final delivered = gateway.deliverToPatcherBus('patcher.fx.swirl.3', 0.5);
      expect(delivered, isTrue);
      expect(gateway.instances[a]!.busSlots[3], 0.5);
    });

    test('an anonymous instance is not bus-addressable', () {
      final a = gateway.createInstance(); // no name → anonymous

      expect(gateway.instances[a]!.busName, '');
      // No registration, so a publish to any patcher address resolves to nothing.
      expect(gateway.deliverToPatcherBus('patcher.anything.0', 1), isFalse);
      expect(gateway.instances[a]!.busSlots, isEmpty);
    });

    test('publishes route to the instance registered under that name', () {
      final a = gateway.createInstance(name: 'a');
      final b = gateway.createInstance(name: 'b');

      gateway.deliverToPatcherBus('patcher.a.0', 1);
      gateway.deliverToPatcherBus('patcher.b.1', 2);

      // Each publish lands only on its own instance — names never cross-talk.
      expect(gateway.instances[a]!.busSlots, {0: 1.0});
      expect(gateway.instances[b]!.busSlots, {1: 2.0});
    });

    test('disposing a named instance unregisters it from the bus', () {
      final a = gateway.createInstance(name: 'gone');
      expect(gateway.deliverToPatcherBus('patcher.gone.0', 1), isTrue);

      gateway.disposeInstance(a);

      // The bus name is freed, so a later publish no longer resolves.
      expect(gateway.deliverToPatcherBus('patcher.gone.0', 2), isFalse);
    });

    test('a malformed patcher address never resolves', () {
      gateway.createInstance(name: 'fx.swirl');

      // Missing slot, non-numeric slot, and wrong prefix all degrade to false.
      expect(gateway.deliverToPatcherBus('patcher.fx.swirl', 1), isFalse);
      expect(gateway.deliverToPatcherBus('patcher.fx.swirl.x', 1), isFalse);
      expect(gateway.deliverToPatcherBus('synth.fx.swirl.0', 1), isFalse);
    });
  });
}
