import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/bus_tap.dart';
import 'package:phi/engine/engine.dart';

import 'test_doubles/fake_bus_tap.dart';
import 'test_doubles/fake_yse_gateway.dart';

/// Proves the host bus tap seam is wired end to end through [PhiEngine] (design
/// `docs/design/live-coding.md` §4, §9 step 1): a publish on the injected tap
/// reaches a Dart listener that subscribed through the engine façade. The tap is
/// silent in production; this exercises the plumbing the live-coding control
/// plane (#233) will hang its `phi.ctl` router on.
void main() {
  late FakeYseGateway gateway;
  late FakeBusTap tap;
  late PhiEngine engine;

  setUp(() {
    gateway = FakeYseGateway();
    tap = FakeBusTap();
    engine = PhiEngine(
      gateway,
      busTap: tap,
      telemetryInterval: const Duration(milliseconds: 20),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await tap.dispose();
    await gateway.dispose();
  });

  test(
    'a fake publish reaches a listener subscribed through the engine',
    () async {
      engine.start();

      final received = <BusTapFrame>[];
      engine.tapBus('phi.ctl').listen(received.add);

      tap.publish('phi.ctl.clip.drums.play', const BusInt(1));
      tap.publish('phi.ctl.var.section', const BusString('b'));
      await pumpEventQueue();

      expect(received, const [
        BusTapFrame('phi.ctl.clip.drums.play', BusInt(1)),
        BusTapFrame('phi.ctl.var.section', BusString('b')),
      ]);
    },
  );

  test('the engine passes the prefix through to the tap', () async {
    engine.start();

    final received = <BusTapFrame>[];
    engine.tapBus('phi.ctl').listen(received.add);

    // A publish outside the subscribed prefix must not surface.
    tap.publish('channel.pads.volume', const BusFloat(0.6));
    await pumpEventQueue();

    expect(received, isEmpty);
  });

  test('the default engine tap is silent', () async {
    final bareGateway = FakeYseGateway();
    final bare = PhiEngine(
      bareGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    addTearDown(bareGateway.dispose);
    addTearDown(bare.dispose);
    bare.start();

    final received = <BusTapFrame>[];
    var done = false;
    bare.tapBus('phi.ctl').listen(received.add, onDone: () => done = true);
    await pumpEventQueue();

    expect(received, isEmpty);
    expect(done, isTrue);
  });
}
