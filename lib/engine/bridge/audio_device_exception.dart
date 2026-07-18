/// Thrown by [YseGateway.openAudioDevice] when a device cannot be opened —
/// either the requested descriptor resolves to no visible device (unplugged,
/// renamed) or the engine refused to open it.
///
/// A bridge-level exception on purpose: `package:yse`'s own `YseException` is an
/// FFI-surface type and must not leak above `lib/engine/bridge/`, so the real
/// gateway catches it and rethrows this. Callers (the boot / live-change apply
/// path, a later issue) catch this to fall back to the previous working device
/// and show a notice (design `docs/design/settings-and-devices.md` §5).
class AudioDeviceException implements Exception {
  /// Builds the exception with a human-readable [message] describing which
  /// device failed and why.
  const AudioDeviceException(this.message);

  /// What went wrong — safe to surface in a notice.
  final String message;

  @override
  String toString() => 'AudioDeviceException: $message';
}
