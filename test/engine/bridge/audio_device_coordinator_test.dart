import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/domain/project/app_settings/speaker_layout.dart';
import 'package:phi/engine/bridge/audio_device_coordinator.dart';
import 'package:phi/engine/bridge/audio_device_descriptor.dart';
import 'package:phi/engine/bridge/audio_device_notice.dart';

import '../test_doubles/fake_yse_gateway.dart';

/// Boot-from-settings + live-switch rules (design §5, §9.3) exercised end to end
/// against the fake gateway — every fallback path, the keep-preference rule, and
/// revert-on-failed-switch (the issue's "Done when").
void main() {
  late FakeYseGateway gateway;
  late List<AudioDeviceNotice> notices;
  late AudioDeviceCoordinator coordinator;

  setUp(() {
    gateway = FakeYseGateway();
    notices = [];
    coordinator = AudioDeviceCoordinator(gateway, onNotice: notices.add);
  });

  tearDown(() => gateway.dispose());

  group('boot — no stored device', () {
    test('opens the platform default via init(), enables auto-reconnect', () {
      coordinator.boot(const AudioSettings());

      expect(gateway.calls, contains('init'));
      expect(gateway.calls.any((c) => c.startsWith('initOffline')), isFalse);
      expect(
        gateway.calls.any((c) => c.startsWith('openAudioDevice')),
        isFalse,
      );
      expect(gateway.autoReconnectOn, isTrue);
      expect(gateway.autoReconnectDelayMs, 1000);
      expect(gateway.calls, contains('setAutoReconnect:true:1000'));
      expect(coordinator.current, const AudioSettings());
      expect(notices, isEmpty);
    });
  });

  group('boot — stored device', () {
    test(
      'initOffline + opens the resolved device (name + host), no notice',
      () {
        const stored = AudioSettings(
          outputHost: 'ASIO',
          outputDevice: 'Fake Interface',
          layout: SpeakerLayout.quad,
        );
        coordinator.boot(stored);

        expect(gateway.calls, containsAllInOrder(<String>['initOffline']));
        // The ASIO entry (not the WASAPI namesake) is the one that opened.
        expect(gateway.openedDevice, gateway.devices[1]);
        expect(gateway.openLayout, SpeakerLayout.quad);
        expect(gateway.autoReconnectOn, isTrue);
        expect(notices, isEmpty);
        expect(coordinator.current.outputDevice, 'Fake Interface');
        expect(coordinator.current.outputHost, 'ASIO');
      },
    );

    test('valid rate + buffer overrides are passed through', () {
      const stored = AudioSettings(
        outputHost: 'WASAPI',
        outputDevice: 'Fake Interface',
        sampleRate: 96000,
        bufferSize: 128,
      );
      coordinator.boot(stored);

      final state = gateway.activeAudioState();
      expect(state.sampleRate, 96000);
      expect(state.bufferSize, 128);
      expect(notices, isEmpty);
    });

    test('an unsupported stored rate falls back to the device default', () {
      // 44100 is not among the ASIO entry's reported rates [48000, 96000].
      const stored = AudioSettings(
        outputHost: 'ASIO',
        outputDevice: 'Fake Interface',
        sampleRate: 44100,
      );
      coordinator.boot(stored);

      expect(gateway.activeSampleRateValue, 48000); // device's first reported
      expect(
        notices.map((n) => n.kind),
        contains(AudioNoticeKind.unsupportedSampleRate),
      );
      // Only the rate reset — the device itself still opened.
      expect(gateway.openedDevice, gateway.devices[1]);
    });

    test('an unsupported stored buffer falls back to the device default', () {
      // 64 is not among the ASIO entry's reported buffers [128, 256].
      const stored = AudioSettings(
        outputHost: 'ASIO',
        outputDevice: 'Fake Interface',
        bufferSize: 64,
      );
      coordinator.boot(stored);

      expect(gateway.activeBufferSizeValue, 128); // device's default buffer
      expect(
        notices.map((n) => n.kind),
        contains(AudioNoticeKind.unsupportedBufferSize),
      );
    });

    test(
      'a missing device falls back to the default and keeps the preference',
      () {
        const stored = AudioSettings(
          outputHost: 'ASIO',
          outputDevice: 'Ghost Device',
        );
        coordinator.boot(stored);

        expect(gateway.calls, contains('initOffline'));
        // Fell back to the platform default (first device).
        expect(gateway.openedDevice, gateway.devices.first);
        expect(coordinator.current.outputDevice, isNull);
        expect(notices.single.kind, AudioNoticeKind.deviceUnavailable);
        // Keep-preference: the coordinator never rewrote the stored value.
        expect(stored.outputDevice, 'Ghost Device');
      },
    );

    test('a present-but-unopenable device falls back to the default', () {
      gateway.devices = const [
        AudioDeviceDescriptor(
          name: 'Default Card',
          hostName: 'WASAPI',
          sampleRates: [48000.0],
          bufferSizes: [256],
          defaultBufferSize: 256,
          outputLatency: 256,
        ),
        AudioDeviceDescriptor(
          name: 'Broken Card',
          hostName: 'ASIO',
          sampleRates: [48000.0],
          bufferSizes: [256],
          defaultBufferSize: 256,
        ),
      ];
      gateway.unopenableDeviceNames.add('Broken Card');

      coordinator.boot(
        const AudioSettings(outputHost: 'ASIO', outputDevice: 'Broken Card'),
      );

      expect(gateway.openedDevice?.name, 'Default Card');
      expect(notices.single.kind, AudioNoticeKind.deviceOpenFailed);
    });

    test('no devices at all — device unavailable then no-audio notice', () {
      gateway.devices = const [];

      coordinator.boot(
        const AudioSettings(outputHost: 'ASIO', outputDevice: 'Ghost'),
      );

      expect(
        notices.map((n) => n.kind),
        containsAllInOrder(<AudioNoticeKind>[
          AudioNoticeKind.deviceUnavailable,
          AudioNoticeKind.noAudioDevice,
        ]),
      );
      expect(coordinator.current, const AudioSettings());
    });
  });

  group('switchTo — live change', () {
    test('opens the target and returns true; current follows', () {
      coordinator.boot(const AudioSettings()); // default
      final ok = coordinator.switchTo(
        const AudioSettings(outputHost: 'ASIO', outputDevice: 'Fake Interface'),
      );

      expect(ok, isTrue);
      expect(gateway.openedDevice, gateway.devices[1]);
      expect(coordinator.current.outputDevice, 'Fake Interface');
      expect(coordinator.current.outputHost, 'ASIO');
    });

    test('re-applying the current target is a no-op (no dropout)', () {
      coordinator.boot(const AudioSettings());
      const target = AudioSettings(
        outputHost: 'ASIO',
        outputDevice: 'Fake Interface',
      );
      coordinator.switchTo(target);
      final opensBefore = gateway.calls
          .where((c) => c.startsWith('openAudioDevice'))
          .length;

      final ok = coordinator.switchTo(target); // already there

      expect(ok, isTrue);
      final opensAfter = gateway.calls
          .where((c) => c.startsWith('openAudioDevice'))
          .length;
      expect(opensAfter, opensBefore); // no extra open
    });

    test('a missing target keeps the current device and returns false', () {
      coordinator.boot(
        const AudioSettings(
          outputHost: 'WASAPI',
          outputDevice: 'Fake Interface',
        ),
      );
      final currentBefore = gateway.openedDevice;

      final ok = coordinator.switchTo(
        const AudioSettings(outputHost: 'ASIO', outputDevice: 'Ghost'),
      );

      expect(ok, isFalse);
      expect(gateway.openedDevice, currentBefore); // untouched
      expect(notices.single.kind, AudioNoticeKind.switchReverted);
    });

    test('a failed open reverts to the previous working device (§9.3)', () {
      gateway.devices = const [
        AudioDeviceDescriptor(
          name: 'Working',
          hostName: 'WASAPI',
          sampleRates: [48000.0],
          bufferSizes: [256],
          defaultBufferSize: 256,
        ),
        AudioDeviceDescriptor(
          name: 'Refuses',
          hostName: 'ASIO',
          sampleRates: [48000.0],
          bufferSizes: [256],
          defaultBufferSize: 256,
        ),
      ];
      gateway.unopenableDeviceNames.add('Refuses');

      coordinator.boot(
        const AudioSettings(outputHost: 'WASAPI', outputDevice: 'Working'),
      );
      expect(coordinator.current.outputDevice, 'Working');

      final ok = coordinator.switchTo(
        const AudioSettings(outputHost: 'ASIO', outputDevice: 'Refuses'),
      );

      expect(ok, isFalse);
      // The engine closed 'Working' before the failed open, so the coordinator
      // reopened it — the last working device wins.
      expect(gateway.openedDevice?.name, 'Working');
      expect(coordinator.current.outputDevice, 'Working');
      expect(notices.last.kind, AudioNoticeKind.switchReverted);
    });
  });
}
