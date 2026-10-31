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

  setUpAll(() {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
  });

  tearDownAll(() => System.instance.close());

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
}
