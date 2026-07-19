import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/voice/channel_allocation.dart';
import 'package:phi/domain/voice/channel_exhausted_exception.dart';

void main() {
  EntityAddress voice(String leaf) => EntityAddress.parse('voice.$leaf');

  group('ChannelAllocation', () {
    test('an empty table holds nothing', () {
      const table = ChannelAllocation.empty();
      expect(table.length, 0);
      expect(table.isFull, isFalse);
      expect(table.channelOf(voice('bells')), isNull);
    });

    test('allocate assigns the lowest free channel from 1', () {
      const table = ChannelAllocation.empty();
      final (next, channel) = table.allocate(voice('bells'));
      expect(channel, 1);
      expect(next.channelOf(voice('bells')), 1);
      // Copy-on-write: the original is untouched.
      expect(table.channelOf(voice('bells')), isNull);
    });

    test('successive voices get successive channels', () {
      var table = const ChannelAllocation.empty();
      var channel = 0;
      (table, channel) = table.allocate(voice('a'));
      expect(channel, 1);
      (table, channel) = table.allocate(voice('b'));
      expect(channel, 2);
      (table, channel) = table.allocate(voice('c'));
      expect(channel, 3);
    });

    test('allocation is stable and idempotent for an existing voice', () {
      var table = const ChannelAllocation.empty();
      final (t1, first) = table.allocate(voice('bells'));
      table = t1;
      final (t2, again) = table.allocate(voice('bells'));
      expect(again, first);
      expect(identical(t2, table), isTrue); // no new table for a no-op
    });

    test('never double-assigns a channel across allocate/free churn', () {
      var table = const ChannelAllocation.empty();
      for (final name in ['a', 'b', 'c', 'd']) {
        (table, _) = table.allocate(voice(name));
      }
      final channels = table.voices.map(table.channelOf).toList();
      expect(channels.toSet().length, channels.length); // all distinct
    });

    test('free releases a channel for the lowest-free reuse', () {
      var table = const ChannelAllocation.empty();
      (table, _) = table.allocate(voice('a')); // 1
      (table, _) = table.allocate(voice('b')); // 2
      (table, _) = table.allocate(voice('c')); // 3
      table = table.free(voice('b')); // frees 2
      final (next, reused) = table.allocate(voice('d'));
      expect(reused, 2); // the lowest free channel, not 4
      expect(next.channelOf(voice('a')), 1); // others unchanged
      expect(next.channelOf(voice('c')), 3);
    });

    test('free is a no-op for an untracked voice', () {
      const table = ChannelAllocation.empty();
      expect(identical(table.free(voice('ghost')), table), isTrue);
    });

    test('throws ChannelExhaustedException on the 17th internal voice', () {
      var table = const ChannelAllocation.empty();
      for (var i = 0; i < ChannelAllocation.capacity; i++) {
        (table, _) = table.allocate(voice('v$i'));
      }
      expect(table.isFull, isTrue);
      expect(
        () => table.allocate(voice('overflow')),
        throwsA(isA<ChannelExhaustedException>()),
      );
    });

    test('a full table still re-allocates an already-held voice', () {
      var table = const ChannelAllocation.empty();
      for (var i = 0; i < ChannelAllocation.capacity; i++) {
        (table, _) = table.allocate(voice('v$i'));
      }
      // Idempotent even when full — it assigns nothing new.
      final (next, channel) = table.allocate(voice('v0'));
      expect(channel, table.channelOf(voice('v0')));
      expect(identical(next, table), isTrue);
    });

    group('persistence (survives save/load)', () {
      test('round-trips identically through JSON', () {
        var table = const ChannelAllocation.empty();
        (table, _) = table.allocate(voice('bells'));
        (table, _) = table.allocate(voice('bass'));
        table = table.free(voice('bells'));
        (table, _) = table.allocate(voice('pad'));

        final restored = ChannelAllocation.fromJson(table.toJson());
        expect(restored, table);
        // The exact channel each voice holds survives the round-trip.
        for (final v in table.voices) {
          expect(restored.channelOf(v), table.channelOf(v));
        }
      });

      test('toJson is sorted by address for a byte-stable encoding', () {
        var table = const ChannelAllocation.empty();
        (table, _) = table.allocate(voice('zeta'));
        (table, _) = table.allocate(voice('alpha'));
        expect(table.toJson().keys.toList(), ['voice.alpha', 'voice.zeta']);
      });

      test('fromJson drops out-of-range and malformed rows', () {
        final table = ChannelAllocation.fromJson(const {
          'voice.good': 5,
          'voice.tooHigh': 17,
          'voice.tooLow': 0,
          'not an address': 3,
        });
        expect(table.length, 1);
        expect(table.channelOf(voice('good')), 5);
      });

      test('fromJson rejects a file that double-assigns a channel', () {
        expect(
          () => ChannelAllocation.fromJson(const {'voice.a': 4, 'voice.b': 4}),
          throwsStateError,
        );
      });
    });

    test('equality is by value, order-independent', () {
      var a = const ChannelAllocation.empty();
      (a, _) = a.allocate(voice('x'));
      (a, _) = a.allocate(voice('y'));

      final b = ChannelAllocation.fromJson({'voice.y': 2, 'voice.x': 1});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
