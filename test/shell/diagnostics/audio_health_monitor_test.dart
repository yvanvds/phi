import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/log/log_source.dart';
import 'package:phi/engine/bridge/audio_device_notice.dart';
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

  setUp(() {
    gateway = FakeYseGateway();
    // Start with a device open (as the engine boots): sampleRate > 0.
    gateway.activeSampleRateValue = 48000;
    gateway.activeBufferSizeValue = 128;
    tick = StreamController<void>.broadcast();
    lastNotice = ValueNotifier<AudioDeviceNotice?>(null);
    notices = NoticeCenter.build();
    monitor = AudioHealthMonitor(
      tick: tick.stream,
      readState: gateway.activeAudioState,
      lastNotice: lastNotice,
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
    final recovery = notices.log.entries.last;
    expect(recovery.level, LogLevel.info);
    expect(recovery.text, contains('recovered'));
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
