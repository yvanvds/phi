import '../project/entity_address.dart';
import 'channel_allocation.dart';
import 'voice_addresses.dart';

/// Resolves a note's `voice.` address to the engine MIDI channel its flattened
/// [TransportNote] rides (design `docs/design/racks-and-voices.md` §6).
///
/// At flatten time the session maps each routed voice to a channel: an
/// **internal** voice to its [allocation] channel, an **external** voice to its
/// configured [externalChannels] channel. A note that carries no voice
/// (`MidiNote.voice == null`, unrouted) resolves to [defaultVoice] — the seeded
/// voice the default chain routes to. A voice that maps to no known channel
/// resolves to `null`, the signal the flatten step degrades gracefully on:
/// the note plays nothing and a warning is surfaced, rather than crashing (§6).
///
/// Channels are returned in Phi's **`0..15`** transport convention (the engine
/// allocation table and external voices carry `1..16`, so this subtracts one),
/// matching [TransportNote]. Pure and immutable — the same voice always resolves
/// the same way — so it is trivially unit-testable and shareable across sessions.
class VoiceChannelResolver {
  const VoiceChannelResolver({
    this.allocation = const ChannelAllocation.empty(),
    this.externalChannels = const {},
    this.defaultVoice = VoiceAddresses.defaultVoice,
  });

  /// A resolver seeded with just [VoiceAddresses.defaultVoice] on the lowest
  /// internal channel — the state a fresh project boots in (`voice.default` →
  /// `synth.sine` → master, §6), before the racks epic materialises further
  /// voices. `voice.default` (and any unrouted note) then resolves to channel 0.
  factory VoiceChannelResolver.seededDefault() {
    final (allocation, _) = const ChannelAllocation.empty().allocate(
      EntityAddress.parse(VoiceAddresses.defaultVoice),
    );
    return VoiceChannelResolver(allocation: allocation);
  }

  /// The internal-voice channel table (`voice address → 1..16`).
  final ChannelAllocation allocation;

  /// Configured MIDI channels for external voices (`voice address → 1..16`),
  /// kept apart from [allocation] because external voices carry their own
  /// channel rather than drawing one from the internal budget (§3).
  final Map<String, int> externalChannels;

  /// The voice an unrouted note (`MidiNote.voice == null`) resolves to.
  final String defaultVoice;

  /// The `0..15` transport channel for [voice], or `null` when it resolves to no
  /// known channel. A `null` [voice] is the unrouted note — it resolves through
  /// [defaultVoice].
  int? channelFor(String? voice) {
    final target = voice ?? defaultVoice;
    final external = externalChannels[target];
    if (external != null) return (external - 1).clamp(0, 15);
    final address = EntityAddress.tryParse(target);
    if (address == null) return null;
    final channel = allocation.channelOf(address);
    if (channel == null) return null;
    return (channel - 1).clamp(0, 15);
  }
}
