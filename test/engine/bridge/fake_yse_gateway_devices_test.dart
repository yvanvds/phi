import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/app_settings/speaker_layout.dart';
import 'package:phi/engine/bridge/audio_device_descriptor.dart';
import 'package:phi/engine/bridge/audio_device_exception.dart';
import 'package:phi/engine/bridge/audio_device_state.dart';

import '../test_doubles/fake_yse_gateway.dart';

/// The fake's device surface is what the (later) settings window is driven
/// against without hardware, so its enumeration, open, and — the issue's
/// explicit ask — open-failure paths are covered here.
void main() {
  late FakeYseGateway gateway;

  setUp(() => gateway = FakeYseGateway());
  tearDown(() => gateway.dispose());

  group('enumeration', () {
    test('audioDevices returns the fabricated list', () {
      final devices = gateway.audioDevices();
      expect(devices, hasLength(2));
      expect(devices.map((d) => d.hostName), ['WASAPI', 'ASIO']);
      expect(devices.first.sampleRates, contains(48000.0));
    });

    test('initOffline records the offline boot path and initialises', () {
      gateway.initOffline();
      expect(gateway.calls, contains('initOffline'));
      expect(gateway.initialised, isTrue);
    });
  });

  // `System::init()` brings the platform default up with it; only
  // `initOffline()` comes up device-less. A fake that skipped this reported a
  // booted app as "no device open", which reads downstream as a device that
  // fell away (issue #398).
  group('init — the platform default comes up with the engine', () {
    test('init brings the default device up in the live state', () {
      gateway.init();
      expect(gateway.initialised, isTrue);
      final state = gateway.activeAudioState();
      expect(state.sampleRate, 44100); // first device, first reported rate
      expect(state.bufferSize, 256); // its default buffer
      expect(state.outputLatency, 256);
    });

    test('init leaves openedDevice alone — that tracks explicit opens', () {
      gateway.init();
      expect(gateway.openedDevice, isNull);
      expect(gateway.calls, ['init']);
    });

    test('initOffline comes up device-less', () {
      gateway.initOffline();
      expect(gateway.activeAudioState().sampleRate, 0);
    });

    test('init on a machine with no audio hardware opens nothing', () {
      gateway.devices = const [];
      gateway.init();
      expect(gateway.activeAudioState().sampleRate, 0);
    });

    test('init when the default refuses to open leaves the state empty', () {
      gateway.unopenableDeviceNames.add('Fake Interface');
      gateway.init();
      expect(gateway.activeAudioState().sampleRate, 0);
    });
  });

  group('openAudioDevice — success', () {
    test('a null descriptor opens the platform default (first device)', () {
      gateway.openAudioDevice(null);
      expect(gateway.openedDevice, gateway.devices.first);
      // The call logs the *passed* args (no overrides → def); the resolved
      // device defaults surface in the active state.
      expect(gateway.calls, contains('openAudioDevice:<default>:def:def:auto'));
      final state = gateway.activeAudioState();
      expect(state.sampleRate, 44100); // first reported rate
      expect(state.bufferSize, 256); // device default buffer
    });

    test(
      'a descriptor resolves by name + host and reflects into active state',
      () {
        final asio = gateway.devices[1]; // Fake Interface on ASIO
        gateway.openAudioDevice(asio, layout: SpeakerLayout.quad);

        expect(gateway.openedDevice, asio);
        expect(gateway.openLayout, SpeakerLayout.quad);
        expect(
          gateway.activeAudioState(),
          const AudioDeviceState(
            sampleRate: 48000,
            bufferSize: 128,
            outputLatency: 128,
          ),
        );
      },
    );

    test('rate + buffer overrides win over the device defaults', () {
      gateway.openAudioDevice(gateway.devices.first, rate: 96000, buffer: 64);
      final state = gateway.activeAudioState();
      expect(state.sampleRate, 96000);
      expect(state.bufferSize, 64);
    });
  });

  group('openAudioDevice — failure paths', () {
    test('an unknown descriptor throws (device unplugged / renamed)', () {
      const missing = AudioDeviceDescriptor(name: 'Ghost', hostName: 'ASIO');
      expect(
        () => gateway.openAudioDevice(missing),
        throwsA(isA<AudioDeviceException>()),
      );
      expect(gateway.openedDevice, isNull);
    });

    test('a present-but-unopenable device throws (engine refuses)', () {
      gateway.unopenableDeviceNames.add('Fake Interface');
      expect(
        () => gateway.openAudioDevice(gateway.devices.first),
        throwsA(isA<AudioDeviceException>()),
      );
    });

    test('a null descriptor with no devices throws', () {
      gateway.devices = const [];
      expect(
        () => gateway.openAudioDevice(null),
        throwsA(isA<AudioDeviceException>()),
      );
    });
  });
}
