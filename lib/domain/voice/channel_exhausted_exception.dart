/// Raised when the channel-allocation table has no free MIDI channel left for a
/// new internal voice — the v1 16-voice ceiling (design
/// `docs/design/racks-and-voices.md` §3, §10 decision 4).
///
/// A domain error, surfaced so a surface can tell the performer the internal
/// voice budget is full rather than silently failing. The ceiling lifts later
/// when yse gains a per-connection channel filter; the allocation table makes
/// that swap invisible.
class ChannelExhaustedException implements Exception {
  /// Builds the error, recording the [capacity] that was reached.
  const ChannelExhaustedException(this.capacity);

  /// The number of internal-voice channels the table holds (16 in v1).
  final int capacity;

  @override
  String toString() =>
      'ChannelExhaustedException: all $capacity internal-voice channels are '
      'allocated (v1 ceiling).';
}
