import 'package:flutter_test/flutter_test.dart';
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
}
