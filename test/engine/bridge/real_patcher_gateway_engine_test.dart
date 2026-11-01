import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:yse/yse.dart';

/// [RealPatcherGateway] against the real engine (issue #442).
///
/// Since yse 0.2.0 the build hook bundles `libyse` for `flutter test` too, so
/// these run headless on an offline session — no audio device needed. They pin
/// the two 0.2.0 contract changes the gateway had to absorb: object IDs are
/// 0-based (0 is a real ID, not the "nothing here" sentinel it was in 0.1.0),
/// and `PCategory` grew eleven categories the descriptor must carry through.
void main() {
  late RealPatcherGateway gateway;
  var engineUp = false;

  setUpAll(() {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
    engineUp = true;
  });

  // Only close what setUpAll actually opened: if the engine failed to load,
  // that failure is the one to report, not a second one from teardown.
  tearDownAll(() {
    if (engineUp) System.instance.close();
  });

  setUp(() => gateway = RealPatcherGateway());

  tearDown(() => gateway.disposeAll());

  test('the first object gets id 0 and a cable into it is enumerated', () {
    final inst = gateway.createInstance();
    final first = gateway.createObject(inst, Obj.dDac);
    final sine = gateway.createObject(inst, Obj.dSine, args: '440');
    expect(first, 0, reason: 'yse 0.2.0 numbers objects from 0');

    gateway.connect(
      inst,
      fromHandleId: sine,
      outlet: 0,
      toHandleId: first,
      inlet: 0,
    );

    final graph = gateway.enumerate(inst);
    expect(graph.objects.map((o) => o.handleId), containsAll([first, sine]));
    expect(graph.connections, hasLength(1));
    final cable = graph.connections.single;
    expect(cable.fromHandleId, sine);
    expect(cable.toHandleId, first, reason: 'a cable into id 0 is real');
    expect(cable.inlet, 0);
  });

  group('named instances (issue #444)', () {
    Future<void> flush() => Future<void>.delayed(Duration.zero);

    Future<List<BusValue>> sendThroughSlot(String name, String address) async {
      final inst = gateway.createInstance(name: name);
      final send = gateway.createObject(inst, Obj.gSend, args: 'cutoff');
      final values = <BusValue>[];
      final sub = Bus.subscribe(address).listen((f) => values.add(f.value));
      addTearDown(sub.cancel);
      gateway.sendFloat(inst, send, 0, 0.25);
      await flush();
      return values;
    }

    test('a .s slot of a named patch publishes at patcher.<name>.<slot>', () {
      expect(
        sendThroughSlot('fx.swirl', 'patcher.fx.swirl.cutoff'),
        completion([const BusFloat(0.25)]),
      );
    });

    test('an over-long name opens anonymous instead of throwing', () async {
      final long = 'x' * (Patcher.maxNameLength + 1);
      expect(RealPatcherGateway.nativeNameFor(long), isNull);
      // The cap callers check against to surface the fallback (issue #452).
      expect(gateway.maxInstanceNameLength, Patcher.maxNameLength);
      expect(await sendThroughSlot(long, 'patcher.$long.cutoff'), isEmpty);
    });

    test('an empty name stays anonymous', () {
      expect(RealPatcherGateway.nativeNameFor(''), isNull);
      expect(RealPatcherGateway.nativeNameFor('fx.swirl'), 'fx.swirl');
    });
  });

  test('objectTypes carries the engine categories through one-to-one', () {
    final byType = {for (final d in gateway.objectTypes()) d.type: d};
    expect(byType['.route']?.category, PatchObjectCategory.routing);
    expect(byType['.pack']?.category, PatchObjectCategory.list);
    expect(
      byType.values.map((d) => d.category).toSet().length,
      greaterThan(8),
      reason: 'more than the eight 0.1.0 categories reach the palette',
    );
  });

  // Issue #482: libYSE 3.1.0 documents `~dac` itself, so the hand-authored
  // fallback (#434) is gone. If the engine ever drops the entry again, the
  // palette and inline completion lose the one object every audible patch
  // needs — this is where that shows up.
  test('objectTypes lists ~dac with the engine\'s own metadata', () {
    final dacs = gateway.objectTypes().where((d) => d.type == Obj.dDac);
    expect(dacs, hasLength(1), reason: 'exactly one ~dac entry');
    final dac = dacs.single;
    final engineDac = PatcherRegistry.types().singleWhere(
      (t) => t.name == Obj.dDac,
    );

    expect(dac.description, engineDac.description);
    expect(dac.description, isNotEmpty, reason: 'documented by the engine');
    expect(
      dac.description,
      isNot('audio output'),
      reason: 'not the old fallback text',
    );
    expect(dac.category, PatchObjectCategory.io);
    expect(dac.isDsp, isTrue);
    expect(dac.inlets, hasLength(2));
    expect(dac.inlets.every((i) => i.isDspInput), isTrue);
    expect(dac.outlets, isEmpty);
  });

  test('isSourceReady: false until mounted, true once the sound is set up, '
      'false again after unmounting (issue #525)', () async {
    final inst = gateway.createInstance();
    final sine = gateway.createObject(inst, Obj.dSine, args: '440');
    final dac = gateway.createObject(inst, Obj.dDac);
    gateway.connect(
      inst,
      fromHandleId: sine,
      outlet: 0,
      toHandleId: dac,
      inlet: 0,
    );
    expect(gateway.isSourceReady(inst), isFalse, reason: 'not mounted');
    gateway.mountAsSource(inst);
    // The worker thread finishes the setup in wall-clock time.
    for (var i = 0; i < 2000 && !gateway.isSourceReady(inst); i++) {
      System.instance
        ..renderOffline(1)
        ..update();
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(gateway.isSourceReady(inst), isTrue);
    gateway.unmountSource(inst);
    expect(gateway.isSourceReady(inst), isFalse, reason: 'unmounted');
    expect(gateway.isSourceReady(999), isFalse, reason: 'no such instance');
  });
}
