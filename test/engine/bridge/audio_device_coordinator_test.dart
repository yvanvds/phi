import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/domain/project/app_settings/speaker_layout.dart';
import 'package:phi/engine/bridge/audio_device_coordinator.dart';
import 'package:phi/engine/bridge/audio_device_descriptor.dart';
import 'package:phi/engine/bridge/audio_device_notice.dart';
import 'package:phi/engine/bridge/audio_device_state.dart';

import '../test_doubles/fake_yse_gateway.dart';

/// The device rules (design §5, §9.3) exercised end to end against the fake
/// gateway. Since issue #405 there is one device path, so every case runs it the
/// way the app does: `boot()` brings the platform default up, then `switchTo`
/// applies a choice — the stored preference at launch (`applyStored` below) or a
/// live pick from the settings window. Both spellings are the *same* call; the
/// grouping only records which moment each rule belongs to.
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

  /// The launch sequence `PhiApp` + `Workstation._startProject` run: engine up
  /// on the platform default, then the just-loaded [stored] settings applied.
  bool applyStored(AudioSettings stored) {
    coordinator.boot();
    return coordinator.switchTo(stored);
  }

  group('boot', () {
    test('opens the platform default via init(), enables auto-reconnect', () {
      coordinator.boot();

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

    test(
      'takes no settings — the stored device cannot be resolved yet (#405)',
      () {
        // `boot()` deliberately has no settings-carrying twin. The engine
        // enumerates hardware only while opening a device (#403), so nothing
        // could be resolved before this `init()` anyway; a second entry point
        // would only be an unrun copy of boot + switch, which is how #403's
        // defect survived. Guarded here by pinning the observable contract:
        // boot opens *no* named device, whatever is stored.
        coordinator.boot();

        expect(gateway.openedDevice, isNull);
        expect(coordinator.current, const AudioSettings());
        // …but it has enumerated, so the very next switch can resolve a name.
        expect(gateway.audioDevices(), isNotEmpty);
      },
    );
  });

  group('boot-from-settings — the stored device applied at launch', () {
    test('opens the resolved device (name + host), no notice', () {
      const stored = AudioSettings(
        outputHost: 'ASIO',
        outputDevice: 'Fake Interface',
        layout: SpeakerLayout.quad,
      );
      final ok = applyStored(stored);

      expect(ok, isTrue);
      expect(gateway.calls, containsAllInOrder(<String>['init']));
      // The ASIO entry (not the WASAPI namesake) is the one that opened.
      expect(gateway.openedDevice, gateway.devices[1]);
      expect(gateway.openLayout, SpeakerLayout.quad);
      expect(gateway.autoReconnectOn, isTrue);
      expect(notices, isEmpty);
      expect(coordinator.current?.outputDevice, 'Fake Interface');
      expect(coordinator.current?.outputHost, 'ASIO');
    });

    test('runs through init(), never initOffline() — an offline engine '
        'enumerates nothing (#403)', () {
      // The regression #403 was about, now pinned on the path the app runs.
      // `initOffline()` leaves the engine with an empty device list (measured
      // against libyse 2.4.0: 0 devices vs 19 after `init()`), so a stored
      // device resolved to "not available", the fallback searched the same
      // empty list, and the app booted silent — while every test passed,
      // because the fake used to hand its fabricated list back on the offline
      // path too.
      applyStored(
        const AudioSettings(outputHost: 'ASIO', outputDevice: 'Fake Interface'),
      );

      expect(gateway.calls.any((c) => c.startsWith('initOffline')), isFalse);
      // The device the performer stored is the device that is open — no
      // "unavailable" notice, no silent boot.
      expect(gateway.audioDevices(), isNotEmpty);
      expect(gateway.openedDevice?.hostName, 'ASIO');
      expect(
        notices.map((n) => n.kind),
        isNot(contains(AudioNoticeKind.noAudioDevice)),
      );
    });

    test('valid rate + buffer overrides are passed through', () {
      const stored = AudioSettings(
        outputHost: 'WASAPI',
        outputDevice: 'Fake Interface',
        sampleRate: 96000,
        bufferSize: 128,
      );
      applyStored(stored);

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
      applyStored(stored);

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
      applyStored(stored);

      expect(gateway.activeBufferSizeValue, 128); // device's default buffer
      expect(
        notices.map((n) => n.kind),
        contains(AudioNoticeKind.unsupportedBufferSize),
      );
    });

    test('a missing device stays on the default and keeps the preference', () {
      const stored = AudioSettings(
        outputHost: 'ASIO',
        outputDevice: 'Ghost Device',
      );
      final ok = applyStored(stored);

      expect(ok, isFalse);
      expect(gateway.calls, contains('init'));
      // The platform default `init()` opened is still the live device — the
      // failed switch never touched it (§9.3).
      expect(gateway.openedDevice, isNull); // no explicit open happened
      expect(
        gateway.activeSampleRateValue,
        gateway.devices.first.sampleRates.first,
      );
      // A device *is* open — the unnamed platform default — which reads as an
      // empty [AudioSettings], never as the `null` that means nothing is open.
      expect(coordinator.current, const AudioSettings());
      expect(notices.single.kind, AudioNoticeKind.switchReverted);
      // Keep-preference: the coordinator never rewrote the stored value.
      expect(stored.outputDevice, 'Ghost Device');
    });

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

      final ok = applyStored(
        const AudioSettings(outputHost: 'ASIO', outputDevice: 'Broken Card'),
      );

      expect(ok, isFalse);
      // The failed open closed the default first, so it was reopened (§9.3).
      expect(gateway.openedDevice?.name, 'Default Card');
      expect(coordinator.current, const AudioSettings());
      // The revert put a device back, so the live state is honest again — the
      // fake zeroes it while the open is failing, as `closeCurrentDevice()` does.
      expect(gateway.activeAudioState().sampleRate, 48000);
      expect(notices.single.kind, AudioNoticeKind.switchReverted);
    });

    test('no devices at all — the switch fails and nothing is open', () {
      // A machine with no audio hardware: `init()` brings no device up, so the
      // boot itself leaves [current] `null` (issue #408) and the stored device
      // has nothing to resolve against.
      gateway.devices = const [];

      final ok = applyStored(
        const AudioSettings(outputHost: 'ASIO', outputDevice: 'Ghost'),
      );

      expect(ok, isFalse);
      expect(notices.single.kind, AudioNoticeKind.switchReverted);
      expect(
        notices.single.message,
        contains('no audio output device is open'),
      );
      expect(coordinator.current, isNull);
      expect(gateway.activeAudioState(), AudioDeviceState.none);
    });

    test('a stored layout without a device still reaches the engine', () {
      // No device name to resolve, but the layout is a stored choice too — the
      // switch opens the platform default with it rather than skipping.
      final ok = applyStored(const AudioSettings(layout: SpeakerLayout.quad));

      expect(ok, isTrue);
      expect(gateway.openLayout, SpeakerLayout.quad);
      expect(notices, isEmpty);
    });

    test('nothing stored is a no-op — no needless dropout at launch', () {
      final ok = applyStored(const AudioSettings());

      expect(ok, isTrue);
      expect(
        gateway.calls.any((c) => c.startsWith('openAudioDevice')),
        isFalse,
      );
      expect(notices, isEmpty);
    });
  });

  group('switchTo — live change', () {
    test('opens the target and returns true; current follows', () {
      coordinator.boot(); // default
      final ok = coordinator.switchTo(
        const AudioSettings(outputHost: 'ASIO', outputDevice: 'Fake Interface'),
      );

      expect(ok, isTrue);
      expect(gateway.openedDevice, gateway.devices[1]);
      expect(coordinator.current?.outputDevice, 'Fake Interface');
      expect(coordinator.current?.outputHost, 'ASIO');
    });

    test('re-applying the current target is a no-op (no dropout)', () {
      coordinator.boot();
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
      applyStored(
        const AudioSettings(
          outputHost: 'WASAPI',
          outputDevice: 'Fake Interface',
        ),
      );
      final currentBefore = gateway.openedDevice;
      notices.clear();

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

      applyStored(
        const AudioSettings(outputHost: 'WASAPI', outputDevice: 'Working'),
      );
      expect(coordinator.current?.outputDevice, 'Working');

      final ok = coordinator.switchTo(
        const AudioSettings(outputHost: 'ASIO', outputDevice: 'Refuses'),
      );

      expect(ok, isFalse);
      // The engine closed 'Working' before the failed open, so the coordinator
      // reopened it — the last working device wins.
      expect(gateway.openedDevice?.name, 'Working');
      expect(coordinator.current?.outputDevice, 'Working');
      expect(notices.last.kind, AudioNoticeKind.switchReverted);
    });

    test('a revert that also fails raises the no-audio notice', () {
      applyStored(
        const AudioSettings(outputHost: 'ASIO', outputDevice: 'Fake Interface'),
      );
      // Every device disappears mid-session — and the open one goes with it, as
      // it does natively: PortAudio errors the stream out and libyse closes it,
      // so `activeAudioState()` reads zero before the switch is even attempted.
      gateway.devices = const [];
      expect(gateway.activeAudioState(), AudioDeviceState.none);
      notices.clear();

      final ok = coordinator.switchTo(const AudioSettings());

      expect(ok, isFalse);
      expect(
        notices.map((n) => n.kind),
        containsAllInOrder(<AudioNoticeKind>[
          AudioNoticeKind.switchReverted,
          AudioNoticeKind.noAudioDevice,
        ]),
      );
      // Nothing is open any more, so [current] is `null` rather than the name of
      // the device that went away (issue #408) — and it agrees with the engine.
      expect(coordinator.current, isNull);
      expect(gateway.activeAudioState(), AudioDeviceState.none);
    });
  });

  group('total loss — nothing is open', () {
    // The one exit where every fallback is exhausted: a switch whose target
    // refuses to open (the engine having already closed the running device) and
    // whose revert finds the previous device gone too. Before issue #408 the
    // coordinator kept naming that previous device, so `activeAudioSettings` —
    // and with it the DIAGNOSTICS row and the pasted report — claimed an output
    // the engine was not on, right next to a live rate of 0.
    const alpha = AudioDeviceDescriptor(
      name: 'Alpha',
      hostName: 'WASAPI',
      sampleRates: [48000.0],
      bufferSizes: [256],
      defaultBufferSize: 256,
      outputLatency: 256,
    );
    const beta = AudioDeviceDescriptor(
      name: 'Beta',
      hostName: 'ASIO',
      sampleRates: [48000.0],
      bufferSizes: [128],
      defaultBufferSize: 128,
      outputLatency: 128,
    );

    /// Drives the loss: boot onto Alpha, then switch to Beta while Beta refuses
    /// and Alpha is unplugged. Faithful to libyse — `openAudioDevice` closes the
    /// running device before it attempts the new one, so the refusal genuinely
    /// leaves the machine device-less, and the revert has nothing to resolve.
    void loseEveryDevice() {
      gateway.devices = const [alpha, beta];
      applyStored(
        const AudioSettings(outputHost: 'WASAPI', outputDevice: 'Alpha'),
      );
      expect(coordinator.current?.outputDevice, 'Alpha');
      notices.clear();

      gateway.unopenableDeviceNames.add('Beta');
      gateway.devices = const [beta]; // Alpha pulled mid-switch
      final ok = coordinator.switchTo(
        const AudioSettings(outputHost: 'ASIO', outputDevice: 'Beta'),
      );
      expect(ok, isFalse);
    }

    test('current reports no device, not the one that went away', () {
      loseEveryDevice();

      expect(coordinator.current, isNull);
      // …and the engine really is on nothing, so no reader can be right by
      // reading `current` and wrong by reading the live state, or vice versa.
      expect(gateway.activeAudioState(), AudioDeviceState.none);
      expect(notices.last.kind, AudioNoticeKind.noAudioDevice);
    });

    test('the notice names the device that was lost, then the loss', () {
      loseEveryDevice();

      expect(notices.first.kind, AudioNoticeKind.switchReverted);
      expect(notices.first.message, contains('reverting to "Alpha"'));
      expect(notices.last.message, contains('No audio output device'));
    });

    test('a retry while nothing is open cannot revert to a phantom', () {
      loseEveryDevice();

      // Beta is visible again but still refuses. There is no previous working
      // device to revert to, so the coordinator says so once and stays honest
      // instead of inventing one.
      notices.clear();
      final ok = coordinator.switchTo(
        const AudioSettings(outputHost: 'ASIO', outputDevice: 'Beta'),
      );

      expect(ok, isFalse);
      expect(coordinator.current, isNull);
      expect(notices.map((n) => n.kind), [AudioNoticeKind.noAudioDevice]);
    });

    test('a target that is not even listed reports the loss, not a device', () {
      loseEveryDevice();
      notices.clear();

      final ok = coordinator.switchTo(
        const AudioSettings(outputHost: 'ASIO', outputDevice: 'Ghost'),
      );

      expect(ok, isFalse);
      expect(coordinator.current, isNull);
      // The "staying on X" phrasing would name a device that is not open.
      expect(
        notices.single.message,
        contains('no audio output device is open'),
      );
      expect(notices.single.message, isNot(contains('Alpha')));
    });

    test('hardware coming back reopens and current names it again', () {
      loseEveryDevice();
      gateway.unopenableDeviceNames.clear();
      gateway.devices = const [alpha, beta];
      notices.clear();

      final ok = coordinator.switchTo(
        const AudioSettings(outputHost: 'WASAPI', outputDevice: 'Alpha'),
      );

      expect(ok, isTrue);
      expect(coordinator.current?.outputDevice, 'Alpha');
      expect(gateway.activeAudioState().sampleRate, 48000);
      expect(notices, isEmpty);
    });

    test('a boot that opens nothing does not claim the default device', () {
      // A machine with no audio hardware at all: `init()` enumerates nothing and
      // brings no device up, so there is nothing for [current] to describe.
      gateway.devices = const [];

      coordinator.boot();

      expect(coordinator.current, isNull);
      expect(gateway.activeAudioState(), AudioDeviceState.none);
    });
  });
}
