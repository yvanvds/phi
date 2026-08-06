/// What Phi's audio-device supervisor is doing right now (issue #410) — the
/// readable half of [AudioDeviceRecovery], carried out of `lib/engine/bridge/`
/// to the surfaces that report it: the status-bar health chip and the
/// diagnostics row / pasted bug report.
///
/// A pure value type — no FFI, no Flutter — so the shell can render "retrying"
/// versus "gave up" without knowing anything about timers or the engine.
class AudioRecoveryStatus {
  /// Builds a status. [retrying] means a further attempt is scheduled;
  /// [gaveUp] means the budget ran out with nothing open; [attempts] counts the
  /// attempts made so far, out of [limit].
  const AudioRecoveryStatus({
    required this.retrying,
    required this.gaveUp,
    required this.attempts,
    required this.limit,
  });

  /// Nothing to recover from — the engine has a device, or has not booted.
  static const AudioRecoveryStatus idle = AudioRecoveryStatus(
    retrying: false,
    gaveUp: false,
    attempts: 0,
    limit: 0,
  );

  /// Whether another attempt is scheduled. While this is true the performer is
  /// told the device is coming back (the chip reads RECONNECTING); audio is
  /// still silent, but not yet a lost cause.
  final bool retrying;

  /// Whether the retry budget was spent without a device coming up. This is the
  /// state that means **recovery is now manual** — the chip reads NO AUDIO and
  /// the performer has to pick a device in the settings window.
  final bool gaveUp;

  /// Attempts made in the current (or just-finished) recovery run.
  final int attempts;

  /// How many attempts the run is allowed — the bound that keeps this from
  /// being a silent infinite retry loop.
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is AudioRecoveryStatus &&
      other.retrying == retrying &&
      other.gaveUp == gaveUp &&
      other.attempts == attempts &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(retrying, gaveUp, attempts, limit);

  @override
  String toString() =>
      'AudioRecoveryStatus(retrying: $retrying, gaveUp: $gaveUp, '
      '$attempts/$limit)';
}
