import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/voice/channel_allocation.dart';
import 'package:phi/domain/voice/voice_addresses.dart';
import 'package:phi/domain/voice/voice_channel_resolver.dart';

void main() {
  group('VoiceChannelResolver', () {
    test('seededDefault maps the default voice (and null) to channel 0', () {
      final resolver = VoiceChannelResolver.seededDefault();
      // The seeded voice is allocated channel 1 (1..16), which is transport
      // channel 0 (0..15).
      expect(resolver.channelFor(VoiceAddresses.defaultVoice), 0);
      // An unrouted note (null voice) routes through the default voice.
      expect(resolver.channelFor(null), 0);
    });

    test('an unknown voice resolves to null (skip + warn)', () {
      final resolver = VoiceChannelResolver.seededDefault();
      expect(resolver.channelFor('voice.ghost'), isNull);
    });

    test('an internal voice maps to its allocation channel, minus one', () {
      final (allocation, _) = const ChannelAllocation.empty()
          .allocate(EntityAddress.parse('voice.a')) // channel 1
          .$1
          .allocate(EntityAddress.parse('voice.b')); // channel 2
      final resolver = VoiceChannelResolver(allocation: allocation);
      expect(resolver.channelFor('voice.a'), 0);
      expect(resolver.channelFor('voice.b'), 1);
    });

    test('an external voice maps to its configured channel, minus one', () {
      const resolver = VoiceChannelResolver(externalChannels: {'voice.hw': 3});
      expect(resolver.channelFor('voice.hw'), 2);
    });

    test('a malformed voice address resolves to null', () {
      final resolver = VoiceChannelResolver.seededDefault();
      expect(resolver.channelFor('not-an-address'), isNull);
    });

    test('the configured default voice is where null routes', () {
      final (allocation, _) = const ChannelAllocation.empty().allocate(
        EntityAddress.parse('voice.lead'),
      );
      final resolver = VoiceChannelResolver(
        allocation: allocation,
        defaultVoice: 'voice.lead',
      );
      expect(resolver.channelFor(null), 0);
      expect(resolver.channelFor('voice.lead'), 0);
    });
  });
}
