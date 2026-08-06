import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/log/log_level.dart';
import '../../engine/bridge/audio_device_notice.dart';
import '../../engine/bridge/audio_device_state.dart';
import '../../engine/bridge/audio_recovery_status.dart';
import 'audio_device_health.dart';
import 'notice_center.dart';

/// Derives the status-bar audio-device [AudioDeviceHealth] (design
/// `docs/design/diagnostics.md` §5) and logs every transition through the notice
/// channel.
///
/// It polls `activeAudioState()` on the engine's existing telemetry [tick] and
/// tracks the most recent device-change / fallback notice (from
/// [PhiEngine.lastAudioNotice]) plus what the recovery supervisor is doing (from
/// [PhiEngine.audioRecovery]) to tell a drop that is being worked on apart from
/// one that is not:
///
/// - a device open (`sampleRate > 0`) → [AudioDeviceHealth.ok];
/// - no device open while Phi is still retrying (issue #410) →
///   [AudioDeviceHealth.reconnecting], *even though* a
///   [AudioNoticeKind.noAudioDevice] notice is standing — the loss is real, but
///   it is not yet the performer's problem;
/// - no device open with that notice standing and no retry left →
///   [AudioDeviceHealth.lost], which now genuinely means "recovery is manual";
/// - no device open otherwise (a drop nothing has reacted to yet) →
///   [AudioDeviceHealth.reconnecting].
///
/// Reaching a healthy device clears the tracked cause, so a later drop reads as
/// reconnecting rather than a stale loss. Every *transition* is surfaced (design
/// §5): dropping to reconnecting/lost raises a notice (toast + log), while
/// recovery back to ok logs at info — through the same channel, without a toast.
class AudioHealthMonitor {
  /// Wires the monitor to the engine's live signals and the notice channel.
  ///
  /// [tick] is the telemetry stream to re-evaluate on (`PhiEngine.telemetry`);
  /// [readState] reads the live device snapshot (`PhiEngine.activeAudioState`);
  /// [lastNotice] is the retained fallback notice (`PhiEngine.lastAudioNotice`);
  /// [readRecovery] reads the supervisor's state (`PhiEngine.audioRecovery`) —
  /// [AudioRecoveryStatus.idle] for a caller with no supervisor; and [notices] is
  /// the channel each transition is surfaced through.
  AudioHealthMonitor({
    required Stream<void> tick,
    required AudioDeviceState Function() readState,
    required ValueListenable<AudioDeviceNotice?> lastNotice,
    required AudioRecoveryStatus Function() readRecovery,
    required NoticeCenter notices,
  }) : _readState = readState,
       _lastNotice = lastNotice,
       _readRecovery = readRecovery,
       _notices = notices {
    _lastNoticeKind = lastNotice.value?.kind;
    _lastNotice.addListener(_onNoticeChanged);
    _tickSub = tick.listen(_onTick);
  }

  final AudioDeviceState Function() _readState;
  final ValueListenable<AudioDeviceNotice?> _lastNotice;
  final AudioRecoveryStatus Function() _readRecovery;
  final NoticeCenter _notices;

  late final StreamSubscription<void> _tickSub;

  /// The most recent fallback notice kind seen since the device was last healthy
  /// — the discriminator between a transient drop and a total loss.
  AudioNoticeKind? _lastNoticeKind;

  final ValueNotifier<AudioDeviceHealth> _health = ValueNotifier(
    AudioDeviceHealth.ok,
  );

  /// The live health the status-bar chip watches.
  ValueListenable<AudioDeviceHealth> get health => _health;

  void _onNoticeChanged() {
    final notice = _lastNotice.value;
    if (notice != null) _lastNoticeKind = notice.kind;
  }

  void _onTick(void _) {
    final deviceOpen = _readState().sampleRate > 0;
    // A standing total-loss notice only reads as *lost* once nothing is trying
    // any more (issue #410). While the supervisor still has attempts left the
    // chip says RECONNECTING, so NO AUDIO keeps one meaning: the retries are
    // over and the next move is the performer's.
    final next = deviceOpen
        ? AudioDeviceHealth.ok
        : (_lastNoticeKind == AudioNoticeKind.noAudioDevice &&
                  !_readRecovery().retrying
              ? AudioDeviceHealth.lost
              : AudioDeviceHealth.reconnecting);
    // A healthy device resets the cause, so the *next* drop reads as a fresh
    // reconnect attempt rather than inheriting an old loss.
    if (deviceOpen) _lastNoticeKind = null;
    if (next == _health.value) return;
    _surface(next);
    _health.value = next;
  }

  /// Logs the transition to [next] through the notice channel (design §5).
  void _surface(AudioDeviceHealth next) {
    switch (next) {
      case AudioDeviceHealth.reconnecting:
        _notices.notice(
          'Audio device dropped — reconnecting…',
          level: LogLevel.warning,
        );
      case AudioDeviceHealth.lost:
        _notices.notice(
          'Audio device lost — running without audio output.',
          level: LogLevel.error,
        );
      case AudioDeviceHealth.ok:
        // Recovery is a quiet trace, not a toast (design §5): log at info.
        _notices.recorder.app('Audio device recovered.', level: LogLevel.info);
    }
  }

  /// Detaches the tick and notice listeners and releases the health notifier.
  void dispose() {
    _lastNotice.removeListener(_onNoticeChanged);
    unawaited(_tickSub.cancel());
    _health.dispose();
  }
}
