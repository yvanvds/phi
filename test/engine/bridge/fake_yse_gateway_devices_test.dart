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

  // Enumeration is a side effect of *opening* a device: the engine's device
  // manager only runs `updateDeviceList()` on the `init(true)` path, and the
  // accessor behind `System.devices` has no lazy refresh (issue #403). Measured
  // against libyse 2.4.0 on Windows — `initOffline()` → 0 devices, `init()` →
  // 19 on the same machine. `real_yse_gateway_enumeration_contract_test.dart`
  // holds the engine itself to this; these hold the fake to the same shape, so
  // the two cannot drift apart the way they did before this issue.
  group('enumeration', () {
    test('audioDevices is empty before the engine has been initialised', () {
      expect(gateway.audioDevices(), isEmpty);
    });

    test('init enumerates the hardware', () {
      gateway.init();

      final devices = gateway.audioDevices();
      expect(devices, hasLength(2));
      expect(devices.map((d) => d.hostName), ['WASAPI', 'ASIO']);
      expect(devices.first.sampleRates, contains(48000.0));
    });

    test('initOffline enumerates nothing — an offline session sees no '
        'hardware at all', () {
      gateway.initOffline();

      expect(gateway.calls, contains('initOffline'));
      expect(gateway.initialised, isTrue);
      expect(gateway.audioDevices(), isEmpty);
      // …and the fabricated hardware is still there to be enumerated later —
      // it is the engine that has not looked, not the machine that is bare.
      expect(gateway.devices, hasLength(2));
    });

    test('an offline session cannot open a device either', () {
      gateway.initOffline();

      // Nothing to resolve against, so even the platform default is refused —
      // which is exactly how the stored-device boot path used to end in
      // silence (issue #403).
      expect(
        () => gateway.openAudioDevice(null),
        throwsA(isA<AudioDeviceException>()),
      );
      expect(
        () => gateway.openAudioDevice(gateway.devices.first),
        throwsA(isA<AudioDeviceException>()),
      );
    });

    test('a second init does not repair an offline session', () {
      // `system::initShared()` early-returns on `Global().active`, so the
      // engine ignores an `init()` that follows an `initOffline()` — measured:
      // the list stays at 0. Only a `close()` first re-enumerates.
      gateway.initOffline();
      gateway.init();

      expect(gateway.audioDevices(), isEmpty);
    });

    test('the enumerated list survives close and a later offline session', () {
      // Measured: after one `init()` the engine's device vector stays filled
      // across `close()` and a subsequent `initOffline()` in the same process.
      // That is why the defect never showed in an in-process restart — only a
      // cold boot went silent.
      gateway.init();
      gateway.close();
      expect(gateway.audioDevices(), hasLength(2));

      gateway.initOffline();
      expect(gateway.audioDevices(), hasLength(2));
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

  // The mirror image of the group above. `close()` is not a recording: the real
  // one closes the MIDI inputs, destroys every channel it minted, and releases
  // the device (`activeSampleRate` is documented to read `0` "after close"). A
  // fake that only flipped `initialised` kept reporting the last opened device
  // and every channel ever created (issue #399).
  group('close — the engine goes down with it', () {
    test('close releases the device', () {
      gateway.init();
      expect(gateway.activeAudioState().sampleRate, 44100);

      gateway.close();

      expect(gateway.initialised, isFalse);
      expect(gateway.activeAudioState(), AudioDeviceState.none);
      expect(gateway.activeSampleRate, 0);
      expect(gateway.activeBufferSize, 0);
      expect(gateway.activeOutputLatency, 0);
    });

    test('close releases an explicitly opened device too', () {
      gateway.init();
      gateway.openAudioDevice(gateway.devices[1], rate: 96000, buffer: 256);
      expect(gateway.activeAudioState().sampleRate, 96000);

      gateway.close();

      expect(gateway.activeAudioState(), AudioDeviceState.none);
    });

    test('close destroys every channel the engine minted', () {
      gateway.init();
      final bus = gateway.createChannel('drums');
      gateway.createChannel('kick', parentId: bus);
      gateway.createReturnChannel('reverb');
      expect(gateway.channels, hasLength(3));

      gateway.close();

      expect(gateway.channels, isEmpty);
      // …and the per-channel reads answer like an unknown id, not a stale one.
      expect(gateway.channelVolume(bus), 0);
      expect(gateway.channelOutputCount(bus), 0);
    });

    test('close does not recycle channel ids', () {
      // `RealYseGateway._destroyAllChannels()` clears the map but leaves
      // `_nextChannelId` counting, so a stale id can never resolve onto a
      // different channel after a restart. A fake that reset to 1 would hide
      // exactly that bug.
      gateway.init();
      final before = gateway.createChannel('drums');
      gateway.close();
      gateway.init();
      final after = gateway.createChannel('drums');

      expect(after, greaterThan(before));
    });

    test('close drops the test signal with the system generating it', () {
      gateway.init();
      gateway.audioTest = true;
      expect(gateway.audioTestOn, isTrue);

      gateway.close();

      expect(gateway.audioTestOn, isFalse);
    });

    test('close zeroes the running engine gauges and meters', () {
      gateway.init();
      gateway
        ..cpuLoadValue = 0.42
        ..masterPeakValue = 0.9
        ..masterPeakOutputs = [0.9, 0.8];

      gateway.close();

      // The device manager zeroes its CPU load average on close, and the
      // master channel loses the implementation its peaks and output count
      // are read from.
      expect(gateway.cpuLoad, 0);
      expect(gateway.masterPeak, 0);
      expect(gateway.masterPeakOutput(0), 0);
      expect(gateway.masterPeakOutput(1), 0);
      expect(gateway.masterOutputCount, 0);
    });

    test('close leaves the stall gauge holding its last value', () {
      // The engine clears `currentlyMissedCallbacks` in `initShared()` and on
      // any `update()` that sees a callback — never in `close()`. Zeroing it
      // here would be an over-model, and an over-model is as much a lie as an
      // under-model. Resetting it on the *init* side is #402.
      gateway.init();
      gateway.deviceStallTicksValue = 7;

      gateway.close();

      expect(gateway.deviceStallTicks, 7);
    });

    test('close stops MIDI traffic reaching listeners', () async {
      final early = <void>[];
      final earlySub = gateway.midiActivity.listen(early.add);
      gateway.emitMidiActivity();
      await Future<void>.delayed(Duration.zero);
      // Nothing is subscribed to a port before init, so nothing arrives.
      expect(early, isEmpty);
      await earlySub.cancel();

      gateway.init();
      final received = <void>[];
      final sub = gateway.midiActivity.listen(received.add);
      gateway.emitMidiActivity();
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));

      gateway.close();
      gateway.emitMidiActivity();
      await Future<void>.delayed(Duration.zero);

      // The real gateway cancelled its port subscriptions; hardware traffic
      // reaches nobody until the engine is initialised again.
      expect(received, hasLength(1));

      gateway.init();
      gateway.emitMidiActivity();
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(2));

      await sub.cancel();
    });

    test('close leaves the diagnostics facts readable', () {
      // Version and library path are available without a device open (design
      // §6), so the diagnostics bundle still reports them after a shutdown.
      gateway.init();
      gateway.close();

      expect(gateway.engineVersion, 'fake-yse 0.0.0');
      expect(gateway.libraryPath, isNotNull);
    });

    test('close leaves the call record and the opened-device record alone', () {
      gateway.init();
      gateway.openAudioDevice(gateway.devices.first);
      gateway.close();

      // These record what a *test* asked for, not live engine state.
      expect(gateway.openedDevice, gateway.devices.first);
      expect(gateway.calls.last, 'close');
      expect(gateway.calls, contains('init'));
    });

    test('init after close brings the default device back up', () {
      gateway.init();
      gateway.close();
      gateway.init();

      expect(gateway.initialised, isTrue);
      expect(
        gateway.activeAudioState(),
        const AudioDeviceState(
          sampleRate: 44100,
          bufferSize: 256,
          outputLatency: 256,
        ),
      );
    });

    test('initOffline after close comes back up device-less', () {
      gateway.init();
      gateway.close();
      gateway.initOffline();

      expect(gateway.activeAudioState(), AudioDeviceState.none);
    });
  });

  group('openAudioDevice — success', () {
    // Every open runs on an enumerated engine, because that is the only kind
    // there is: the device list exists because `init()` opened one (#403).
    setUp(() => gateway.init());

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
    setUp(() => gateway.init());

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
