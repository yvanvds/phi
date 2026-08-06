import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/log/log_source.dart';
import 'package:phi/engine/bridge/audio_device_notice.dart';
import 'package:phi/engine/bridge/audio_recovery_status.dart';
import 'package:phi/shell/diagnostics/audio_device_health.dart';
import 'package:phi/shell/diagnostics/audio_health_monitor.dart';
import 'package:phi/shell/diagnostics/notice_center.dart';

import '../../engine/test_doubles/fake_yse_gateway.dart';

/// Unit coverage for [AudioHealthMonitor] (design `docs/design/diagnostics.md`
/// §5): the ok → reconnecting → lost → ok derivation off `activeAudioState()`
/// (read here through the fake gateway) plus device notices, and the paired log
/// entries each transition writes through the notice channel.
void main() {
  late FakeYseGateway gateway;
  late StreamController<void> tick;
  late ValueNotifier<AudioDeviceNotice?> lastNotice;
  late NoticeCenter notices;
  late AudioHealthMonitor monitor;

  /// What the supervisor reports on the next tick — idle unless a test is
  /// exercising the recovery window (issue #410).
  late AudioRecoveryStatus recovery;

  setUp(() {
    gateway = FakeYseGateway();
    // Start with a device open (as the engine boots): sampleRate > 0.
    gateway.activeSampleRateValue = 48000;
    gateway.activeBufferSizeValue = 128;
    tick = StreamController<void>.broadcast();
    lastNotice = ValueNotifier<AudioDeviceNotice?>(null);
    notices = NoticeCenter.build();
    recovery = AudioRecoveryStatus.idle;
    monitor = AudioHealthMonitor(
      tick: tick.stream,
      readState: gateway.activeAudioState,
      lastNotice: lastNotice,
      readRecovery: () => recovery,
      notices: notices,
    );
  });

  tearDown(() async {
    monitor.dispose();
    notices.dispose();
    lastNotice.dispose();
    await tick.close();
    await gateway.dispose();
  });

  void fireTick() => tick.add(null);

  // Wait for the broadcast tick event to reach the monitor's listener.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('starts ok and stays ok while a device is open — no notice', () async {
    expect(monitor.health.value, AudioDeviceHealth.ok);

    fireTick();
    await settle();

    expect(monitor.health.value, AudioDeviceHealth.ok);
    expect(notices.log.entries, isEmpty);
    expect(notices.toasts.visible, isEmpty);
  });

  test('a dropped device with no loss notice reads as reconnecting (warning '
      'notice)', () async {
    gateway.activeSampleRateValue = 0; // the device fell away
    fireTick();
    await settle();

    expect(monitor.health.value, AudioDeviceHealth.reconnecting);
    // Toast + log entry (a surfaced notice).
    expect(notices.toasts.visible, hasLength(1));
    final entry = notices.log.entries.single;
    expect(entry.source, LogSource.app);
    expect(entry.level, LogLevel.warning);
    expect(entry.text, contains('reconnecting'));
  });

  test(
    'a noAudioDevice notice while dropped reads as lost (error notice)',
    () async {
      gateway.activeSampleRateValue = 0;
      lastNotice.value = const AudioDeviceNotice(
        AudioNoticeKind.noAudioDevice,
        'No audio output device is available.',
      );
      fireTick();
      await settle();

      expect(monitor.health.value, AudioDeviceHealth.lost);
      expect(notices.toasts.visible, hasLength(1));
      final entry = notices.log.entries.single;
      expect(entry.level, LogLevel.error);
      expect(entry.text, contains('lost'));
    },
  );

  group('the recovery window (issue #410)', () {
    // A total loss now arms Phi's own bounded retry, so the standing
    // `noAudioDevice` notice is no longer enough to call it lost: while the
    // supervisor has attempts left the chip must keep saying RECONNECTING, and
    // only settle on NO AUDIO once the budget is spent. Otherwise NO AUDIO means
    // two different things — "wait" and "your move" — and the performer cannot
    // tell which one they are looking at.
    const standing = AudioDeviceNotice(
      AudioNoticeKind.noAudioDevice,
      'No audio output device could be opened.',
    );

    test('a total loss reads as reconnecting while retries remain', () async {
      gateway.activeSampleRateValue = 0;
      lastNotice.value = standing;
      recovery = const AudioRecoveryStatus(
        retrying: true,
        gaveUp: false,
        attempts: 1,
        limit: 8,
      );
      fireTick();
      await settle();

      expect(monitor.health.value, AudioDeviceHealth.reconnecting);
      // The louder "lost" wording is held back until it is actually true.
      expect(notices.log.entries.single.level, LogLevel.warning);
      expect(notices.log.entries.single.text, contains('reconnecting'));
    });

    test('it becomes lost the moment the supervisor gives up', () async {
      gateway.activeSampleRateValue = 0;
      lastNotice.value = standing;
      recovery = const AudioRecoveryStatus(
        retrying: true,
        gaveUp: false,
        attempts: 3,
        limit: 8,
      );
      fireTick();
      await settle();
      expect(monitor.health.value, AudioDeviceHealth.reconnecting);

      // The budget runs out — nothing is trying any more.
      recovery = const AudioRecoveryStatus(
        retrying: false,
        gaveUp: true,
        attempts: 8,
        limit: 8,
      );
      fireTick();
      await settle();

      expect(monitor.health.value, AudioDeviceHealth.lost);
      expect(notices.log.entries.last.level, LogLevel.error);
      expect(notices.log.entries.last.text, contains('lost'));
    });

    test('a recovery that succeeds mid-run returns the chip to ok', () async {
      gateway.activeSampleRateValue = 0;
      lastNotice.value = standing;
      recovery = const AudioRecoveryStatus(
        retrying: true,
        gaveUp: false,
        attempts: 2,
        limit: 8,
      );
      fireTick();
      await settle();
      expect(monitor.health.value, AudioDeviceHealth.reconnecting);

      // An attempt lands: a device is open again and the run stands down.
      gateway.activeSampleRateValue = 48000;
      recovery = AudioRecoveryStatus.idle;
      fireTick();
      await settle();

      expect(monitor.health.value, AudioDeviceHealth.ok);
      expect(notices.log.entries.last.text, contains('recovered'));
      // Only the drop toasted — the recovery is a quiet trace.
      expect(notices.toasts.visible, hasLength(1));
    });
  });

  test('recovery to ok logs at info without a toast', () async {
    // Drop → reconnecting (one toast, one log), then recover.
    gateway.activeSampleRateValue = 0;
    fireTick();
    await settle();
    expect(monitor.health.value, AudioDeviceHealth.reconnecting);

    gateway.activeSampleRateValue = 48000; // device back
    fireTick();
    await settle();

    expect(monitor.health.value, AudioDeviceHealth.ok);
    // Recovery is a quiet info trace — no *new* toast beyond the reconnect one.
    expect(notices.toasts.visible, hasLength(1));
    final recovered = notices.log.entries.last;
    expect(recovered.level, LogLevel.info);
    expect(recovered.text, contains('recovered'));
  });

  test('walks ok → reconnecting → lost → ok with paired log entries', () async {
    // ok (already), no entries yet.
    fireTick();
    await settle();
    expect(monitor.health.value, AudioDeviceHealth.ok);

    // reconnecting: device drops, no loss notice yet.
    gateway.activeSampleRateValue = 0;
    fireTick();
    await settle();
    expect(monitor.health.value, AudioDeviceHealth.reconnecting);

    // lost: a total-loss notice arrives while still dropped.
    lastNotice.value = const AudioDeviceNotice(
      AudioNoticeKind.noAudioDevice,
      'No audio output device is available.',
    );
    fireTick();
    await settle();
    expect(monitor.health.value, AudioDeviceHealth.lost);

    // ok: a device opens again — the stale loss cause is cleared.
    gateway.activeSampleRateValue = 44100;
    fireTick();
    await settle();
    expect(monitor.health.value, AudioDeviceHealth.ok);

    // Three transitions, three paired log entries in order.
    final levels = notices.log.entries.map((e) => e.level).toList();
    expect(levels, <LogLevel>[
      LogLevel.warning, // → reconnecting
      LogLevel.error, // → lost
      LogLevel.info, // → recovered
    ]);
    // reconnecting and lost toasted; recovery did not.
    expect(notices.toasts.visible, hasLength(2));

    // A subsequent drop (no new loss notice) reads as reconnecting again — the
    // earlier noAudioDevice was cleared on recovery, not carried forward.
    gateway.activeSampleRateValue = 0;
    fireTick();
    await settle();
    expect(monitor.health.value, AudioDeviceHealth.reconnecting);
  });
}
