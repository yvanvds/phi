import 'package:flutter_test/flutter_test.dart';

import '../test_doubles/fake_yse_gateway.dart';

/// The mix surface (channel tree, return buses, aux sends, per-output meters)
/// must be fully drivable against the fake without audio hardware — this is
/// the gateway half of the mix epic (issue #167). These tests exercise the
/// fake's tree/returns/sends/metering, including the illegal-wiring no-ops the
/// real engine rejects and logs (design `docs/design/mix.md` §4).
void main() {
  late FakeYseGateway gateway;

  setUp(() => gateway = FakeYseGateway());
  tearDown(() => gateway.dispose());

  group('channel tree', () {
    test('createChannel defaults to a child of master', () {
      final id = gateway.createChannel('kick');
      expect(gateway.channels[id]!.parentId, isNull);
      expect(gateway.channels[id]!.isReturn, isFalse);
      expect(gateway.calls, contains('createChannel:$id:kick:master'));
    });

    test('createChannel nests under an explicit parent', () {
      final group = gateway.createChannel('drums');
      final child = gateway.createChannel('snare', parentId: group);
      expect(gateway.channels[child]!.parentId, group);
      expect(gateway.calls, contains('createChannel:$child:snare:$group'));
    });

    test('moveChannel re-parents to a group then back to master', () {
      final group = gateway.createChannel('drums');
      final strip = gateway.createChannel('snare');

      gateway.moveChannel(strip, group);
      expect(gateway.channels[strip]!.parentId, group);
      expect(gateway.calls, contains('moveChannel:$strip:$group'));

      gateway.moveChannel(strip); // null parent = master
      expect(gateway.channels[strip]!.parentId, isNull);
      expect(gateway.calls, contains('moveChannel:$strip:master'));
    });

    test('moveChannel on an unknown id is a no-op', () {
      expect(() => gateway.moveChannel(999, 1), returnsNormally);
    });

    test('destroyChannel drops the channel', () {
      final id = gateway.createChannel('temp');
      gateway.destroyChannel(id);
      expect(gateway.channels.containsKey(id), isFalse);
    });
  });

  group('return buses', () {
    test('createReturnChannel marks a return with the default four slots', () {
      final id = gateway.createReturnChannel('verb');
      expect(gateway.channels[id]!.isReturn, isTrue);
      expect(gateway.channels[id]!.sendSlots, 4);
      expect(gateway.calls, contains('createReturnChannel:$id:verb:4'));
    });

    test('createReturnChannel sizes its onward-send slots', () {
      final id = gateway.createReturnChannel('verb', sendSlots: 8);
      expect(gateway.channels[id]!.sendSlots, 8);
      expect(gateway.calls, contains('createReturnChannel:$id:verb:8'));
    });

    test('an ordinary channel keeps four slots regardless', () {
      final id = gateway.createChannel('kick');
      expect(gateway.channels[id]!.sendSlots, 4);
    });
  });

  group('aux sends — legal wiring', () {
    late int strip;
    late int verb;

    setUp(() {
      strip = gateway.createChannel('kick');
      verb = gateway.createReturnChannel('verb');
    });

    test('setSend wires a slot to a return, recording level and tap', () {
      gateway.setSend(strip, 0, verb, 0.4, true);
      final send = gateway.channels[strip]!.sends[0]!;
      expect(send.returnId, verb);
      expect(send.level, 0.4);
      expect(send.preFader, isTrue);
      expect(gateway.calls, contains('setSend:$strip:0:$verb:0.400:true'));
    });

    test('setSendLevel updates the level of a wired slot', () {
      gateway.setSend(strip, 1, verb, 0.2, false);
      gateway.setSendLevel(strip, 1, 0.9);
      expect(gateway.channels[strip]!.sends[1]!.level, 0.9);
      expect(gateway.calls, contains('setSendLevel:$strip:1:0.900'));
    });

    test('setSendLevel on an unset slot is a no-op', () {
      gateway.setSendLevel(strip, 2, 0.5);
      expect(gateway.channels[strip]!.sends.containsKey(2), isFalse);
    });

    test('clearSend detaches a slot', () {
      gateway.setSend(strip, 0, verb, 0.5, false);
      gateway.clearSend(strip, 0);
      expect(gateway.channels[strip]!.sends.containsKey(0), isFalse);
      expect(gateway.calls, contains('clearSend:$strip:0'));
    });

    test('a return may send onward into another return', () {
      final delay = gateway.createReturnChannel('delay');
      gateway.setSend(delay, 0, verb, 0.3, false);
      expect(gateway.channels[delay]!.sends[0]!.returnId, verb);
    });
  });

  group('aux sends — illegal wiring is a no-op', () {
    test('a non-return target is rejected', () {
      final strip = gateway.createChannel('kick');
      final other = gateway.createChannel('snare');
      gateway.setSend(strip, 0, other, 0.5, false);
      expect(gateway.channels[strip]!.sends, isEmpty);
    });

    test('a self-send is rejected', () {
      final verb = gateway.createReturnChannel('verb');
      gateway.setSend(verb, 0, verb, 0.5, false);
      expect(gateway.channels[verb]!.sends, isEmpty);
    });

    test('an out-of-range slot is rejected', () {
      final strip = gateway.createChannel('kick');
      final verb = gateway.createReturnChannel('verb');
      gateway.setSend(strip, 4, verb, 0.5, false); // slots are 0..3
      gateway.setSend(strip, -1, verb, 0.5, false);
      expect(gateway.channels[strip]!.sends, isEmpty);
    });

    test('a return -> return edge that would close a cycle is rejected', () {
      final verb = gateway.createReturnChannel('verb');
      final delay = gateway.createReturnChannel('delay');
      gateway.setSend(delay, 0, verb, 0.3, false); // delay -> verb (ok)
      gateway.setSend(verb, 0, delay, 0.3, false); // verb -> delay closes cycle
      expect(gateway.channels[verb]!.sends, isEmpty);
      expect(gateway.channels[delay]!.sends[0]!.returnId, verb);
    });

    test('a send from or to an unknown channel is a no-op', () {
      final verb = gateway.createReturnChannel('verb');
      expect(() => gateway.setSend(999, 0, verb, 0.5, false), returnsNormally);
      final strip = gateway.createChannel('kick');
      gateway.setSend(strip, 0, 999, 0.5, false);
      expect(gateway.channels[strip]!.sends, isEmpty);
    });
  });

  group('per-output metering', () {
    test('channelOutputCount and per-output peaks read seeded values', () {
      final id = gateway.createChannel('kick');
      gateway.channels[id]!
        ..outputCount = 4
        ..peakOutputs = [0.1, 0.2, 0.3, 0.4]
        ..prePeakOutputs = [0.5, 0.6, 0.7, 0.8];

      expect(gateway.channelOutputCount(id), 4);
      expect(gateway.channelPeakOutput(id, 2), 0.3);
      expect(gateway.channelPeakPreOutput(id, 3), 0.8);
    });

    test('out-of-range and unknown channel meters read zero', () {
      final id = gateway.createChannel('kick'); // default stereo
      expect(gateway.channelPeakOutput(id, 5), 0);
      expect(gateway.channelPeakPreOutput(id, -1), 0);
      expect(gateway.channelOutputCount(404), 0);
      expect(gateway.channelPeakOutput(404, 0), 0);
    });

    test('master exposes per-output count and post peaks', () {
      gateway.masterOutputCountValue = 6;
      gateway.masterPeakOutputs = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6];
      expect(gateway.masterOutputCount, 6);
      expect(gateway.masterPeakOutput(4), 0.5);
      expect(gateway.masterPeakOutput(6), 0); // out of range
    });
  });
}
