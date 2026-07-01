/// Thrown when a byte stream can't be parsed as a Standard MIDI File.
///
/// Carries a human-readable [message] and the byte [offset] at which parsing
/// gave up (or `-1` when the failure isn't tied to a position, e.g. a missing
/// header). The surface layer surfaces this to the user rather than crashing
/// when a dropped file turns out not to be a valid `.mid`.
class SmfFormatException implements Exception {
  const SmfFormatException(this.message, [this.offset = -1]);

  final String message;
  final int offset;

  @override
  String toString() => offset >= 0
      ? 'SmfFormatException: $message (at byte $offset)'
      : 'SmfFormatException: $message';
}
