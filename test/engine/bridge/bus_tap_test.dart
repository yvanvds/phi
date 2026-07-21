import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/bus_tap.dart';
import 'package:phi/engine/bridge/no_op_bus_tap.dart';

import '../test_doubles/fake_bus_tap.dart';

void main() {
  group('busAddressMatchesPrefix', () {
    test('an exact match and any dotted child match', () {
      expect(busAddressMatchesPrefix('phi.ctl', 'phi.ctl'), isTrue);
      expect(
        busAddressMatchesPrefix('phi.ctl.clip.drums.play', 'phi.ctl'),
        isTrue,
      );
    });

    test('a same-prefix-but-different-segment address does not match', () {
      // `phi.ctlx` shares the character prefix but not the segment boundary.
      expect(busAddressMatchesPrefix('phi.ctlx', 'phi.ctl'), isFalse);
      expect(busAddressMatchesPrefix('phi.other.x', 'phi.ctl'), isFalse);
    });
  });

  group('BusValue equality', () {
    test('same-typed values compare equal, cross-typed do not', () {
      expect(const BusInt(60), const BusInt(60));
      expect(const BusFloat(0.5), const BusFloat(0.5));
      expect(const BusString('b'), const BusString('b'));
      expect(const BusFloatList([0.1, 0.2]), const BusFloatList([0.1, 0.2]));

      expect(const BusInt(60) == const BusFloat(60), isFalse);
      expect(const BusFloatList([0.1]) == const BusFloatList([0.2]), isFalse);
    });

    test('frames compare by address and value', () {
      expect(
        const BusTapFrame('phi.ctl.a', BusInt(1)),
        const BusTapFrame('phi.ctl.a', BusInt(1)),
      );
      expect(
        const BusTapFrame('phi.ctl.a', BusInt(1)) ==
            const BusTapFrame('phi.ctl.b', BusInt(1)),
        isFalse,
      );
    });
  });

  group('FakeBusTap', () {
    late FakeBusTap tap;

    setUp(() => tap = FakeBusTap());
    tearDown(() => tap.dispose());

    test(
      'a publish reaches a Dart listener, carrying each bus value type',
      () async {
        final received = <BusTapFrame>[];
        tap.subscribe('phi.ctl').listen(received.add);

        tap.publish('phi.ctl.voice.bells.note', const BusInt(60));
        tap.publish('phi.ctl.mix.pads.volume', const BusFloat(0.6));
        tap.publish('phi.ctl.var.section', const BusString('b'));
        tap.publish(
          'phi.ctl.voice.bells.chord',
          const BusFloatList([60, 64, 67]),
        );

        await pumpEventQueue();

        expect(received, const [
          BusTapFrame('phi.ctl.voice.bells.note', BusInt(60)),
          BusTapFrame('phi.ctl.mix.pads.volume', BusFloat(0.6)),
          BusTapFrame('phi.ctl.var.section', BusString('b')),
          BusTapFrame('phi.ctl.voice.bells.chord', BusFloatList([60, 64, 67])),
        ]);
      },
    );

    test('only publishes under the subscribed prefix are delivered', () async {
      final received = <BusTapFrame>[];
      tap.subscribe('phi.ctl').listen(received.add);

      tap.publish('phi.ctl.clip.drums.play', const BusInt(1));
      tap.publish('channel.pads.volume', const BusFloat(0.6)); // engine-direct
      tap.publish('phi.ctlx.spoof', const BusInt(9)); // not a segment child

      await pumpEventQueue();

      expect(received, const [
        BusTapFrame('phi.ctl.clip.drums.play', BusInt(1)),
      ]);
    });

    test('the stream is broadcast — multiple listeners each receive', () async {
      final a = <BusTapFrame>[];
      final b = <BusTapFrame>[];
      tap.subscribe('phi.ctl').listen(a.add);
      tap.subscribe('phi.ctl').listen(b.add);

      tap.publish('phi.ctl.state.fire', const BusString('verse'));
      await pumpEventQueue();

      expect(a, const [BusTapFrame('phi.ctl.state.fire', BusString('verse'))]);
      expect(b, const [BusTapFrame('phi.ctl.state.fire', BusString('verse'))]);
    });
  });

  group('NoOpBusTap', () {
    test('yields an empty stream and never emits a frame', () async {
      const tap = NoOpBusTap();
      final received = <BusTapFrame>[];
      var done = false;
      tap.subscribe('phi.ctl').listen(received.add, onDone: () => done = true);

      await pumpEventQueue();

      expect(received, isEmpty);
      expect(done, isTrue);
      await tap.dispose(); // safe, idempotent
    });
  });
}
