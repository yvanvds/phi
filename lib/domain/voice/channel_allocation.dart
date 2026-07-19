import '../project/entity_address.dart';
import 'channel_exhausted_exception.dart';

/// The internal-voice channel-allocation table (design
/// `docs/design/racks-and-voices.md` §3, §10 decision 4).
///
/// Every **internal** voice gets a stable engine MIDI channel in `[1, 16]`,
/// assigned at voice creation and freed on delete. The table is the authority for
/// that mapping: it never double-assigns a channel, and it refuses a 17th
/// internal voice with a [ChannelExhaustedException] — the accepted v1 ceiling.
/// It is persisted so a voice keeps its channel across save/reload (external
/// voices carry their own channel and are not tracked here).
///
/// An **immutable, copy-on-write** value type: [allocate] and [free] return a new
/// table rather than mutating in place, so undo and journalling are trivial, and
/// two tables compare by value. Addresses serialise in dotted string form.
class ChannelAllocation {
  const ChannelAllocation._(this._byVoice);

  /// An empty table — no channels assigned.
  const ChannelAllocation.empty() : _byVoice = const {};

  /// Rebuilds a table from a decoded `voice address → channel` map (the
  /// persisted form). Skips entries whose channel is out of `[1, 16]` or whose
  /// address is malformed — a corrupt row is dropped, not fatal. Throws a
  /// [StateError] only if the decoded rows double-assign a channel, which a
  /// well-formed file never does.
  factory ChannelAllocation.fromJson(Map<String, Object?> json) {
    final byVoice = <EntityAddress, int>{};
    final used = <int>{};
    for (final entry in json.entries) {
      final channel = (entry.value as num?)?.toInt();
      if (channel == null || channel < minChannel || channel > maxChannel) {
        continue;
      }
      final address = EntityAddress.tryParse(entry.key);
      if (address == null) continue;
      if (!used.add(channel)) {
        throw StateError(
          'Corrupt channel allocation: channel $channel assigned twice.',
        );
      }
      byVoice[address] = channel;
    }
    return ChannelAllocation._(Map.unmodifiable(byVoice));
  }

  /// The lowest engine channel voices are assigned (0 is the engine's omni
  /// channel, reserved).
  static const int minChannel = 1;

  /// The highest engine channel — the top of the MIDI channel space.
  static const int maxChannel = 16;

  /// How many internal voices the table can hold — the v1 ceiling.
  static const int capacity = maxChannel - minChannel + 1;

  final Map<EntityAddress, int> _byVoice;

  /// The channel assigned to [voice], or `null` when it holds none.
  int? channelOf(EntityAddress voice) => _byVoice[voice];

  /// Whether [voice] currently holds a channel.
  bool contains(EntityAddress voice) => _byVoice.containsKey(voice);

  /// Whether every channel is assigned — the next [allocate] of a new voice
  /// throws.
  bool get isFull => _byVoice.length >= capacity;

  /// The number of voices currently holding a channel.
  int get length => _byVoice.length;

  /// The tracked voices, in no guaranteed order.
  Iterable<EntityAddress> get voices => _byVoice.keys;

  /// A read-only view of the `voice → channel` mapping.
  Map<EntityAddress, int> get entries => _byVoice;

  /// Assigns [voice] the lowest free channel and returns the new table plus that
  /// channel. **Idempotent:** a voice that already holds a channel keeps it (the
  /// same table is returned unchanged). Throws a [ChannelExhaustedException] when
  /// all [capacity] channels are taken and [voice] is new.
  (ChannelAllocation, int) allocate(EntityAddress voice) {
    final existing = _byVoice[voice];
    if (existing != null) return (this, existing);
    final channel = _lowestFreeChannel();
    if (channel == null) throw const ChannelExhaustedException(capacity);
    return (
      ChannelAllocation._(Map.unmodifiable({..._byVoice, voice: channel})),
      channel,
    );
  }

  /// Returns a table with [voice]'s channel released — freeing it for reuse. A
  /// no-op (the same table) when [voice] holds none.
  ChannelAllocation free(EntityAddress voice) {
    if (!_byVoice.containsKey(voice)) return this;
    final next = Map<EntityAddress, int>.from(_byVoice)..remove(voice);
    return ChannelAllocation._(Map.unmodifiable(next));
  }

  /// The table as its JSON map (`dotted address → channel`), entries sorted by
  /// address so an unchanged table re-encodes byte-identically.
  Map<String, Object?> toJson() {
    final keys = _byVoice.keys.map((a) => a.format()).toList()..sort();
    return {for (final key in keys) key: _byVoice[EntityAddress.parse(key)]};
  }

  int? _lowestFreeChannel() {
    final used = _byVoice.values.toSet();
    for (var channel = minChannel; channel <= maxChannel; channel++) {
      if (!used.contains(channel)) return channel;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelAllocation && _sameMapping(other._byVoice, _byVoice);

  @override
  int get hashCode {
    // Order-independent hash over the (address, channel) pairs.
    var hash = 0;
    for (final entry in _byVoice.entries) {
      hash ^= Object.hash(entry.key, entry.value);
    }
    return hash;
  }

  @override
  String toString() => 'ChannelAllocation($_byVoice)';

  static bool _sameMapping(
    Map<EntityAddress, int> a,
    Map<EntityAddress, int> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
