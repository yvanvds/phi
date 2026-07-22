/// The health of the currently open audio device (design
/// `docs/design/diagnostics.md` §5) — what the status-bar audio-device chip
/// shows at a glance.
///
/// Derived by [AudioHealthMonitor] from `activeAudioState()` polled on the
/// engine's telemetry tick plus the device-change / fallback notices: a running
/// device is [ok], a device that dropped while auto-reconnect tries to bring it
/// back is [reconnecting], and a total loss (nothing could be opened at all) is
/// [lost].
enum AudioDeviceHealth {
  /// A device is open and producing audio — the calm, glanceable default.
  ok,

  /// The device dropped and the engine's 1 s auto-reconnect is trying to reopen
  /// it — a transient, recoverable degradation.
  reconnecting,

  /// No audio device could be opened at all — the engine is running silent.
  lost,
}
