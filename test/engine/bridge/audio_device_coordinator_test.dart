import 'package:fake_async/fake_async.dart';
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

  /// The retry cadence the coordinator's recovery runs on in these tests — three
  /// attempts one second apart, so a whole run (including the give-up) fits in a
  /// `fakeAsync` elapse instead of the shipped two minutes.
  const recoverySchedule = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 1),
    Duration(seconds: 1),
  ];

  setUp(() {
    gateway = FakeYseGateway();
    notices = [];
    coordinator = AudioDeviceCoordinator(
      gateway,
      onNotice: notices.add,
      recoverySchedule: recoverySchedule,
    );
  });

  tearDown(() {
    // The coordinator owns a retry timer since issue #410 — leaving it armed
    // fails the test with a pending timer, which is exactly the signal we want
    // if a path ever forgets to stand recovery down.
    coordinator.dispose();
    return gateway.dispose();
  });

  /// The launch sequence `PhiApp` + `Workstation._startProject` run: engine up
  /// on the platform default, then the just-loaded [stored] settings applied.
  bool applyStored(AudioSettings stored) {
    coordinator.boot();
    return coordinator.switchTo(stored);
  }

  group('boot', () {
    test(
      'opens the platform default via init(), engine auto-reconnect off',
      () {
        coordinator.boot();

        expect(gateway.calls, contains('init'));
        expect(gateway.calls.any((c) => c.startsWith('initOffline')), isFalse);
        expect(
          gateway.calls.any((c) => c.startsWith('openAudioDevice')),
          isFalse,
        );
        // Design §4 used to arm the engine's own auto-reconnect here. It is off
        // since issue #410: measured against libyse, it reopens
        // `Pa_GetDefaultOutputDevice()` rather than the device that was lost,
        // drops the chosen buffer size, and once armed retries on every 16 ms
        // control tick forever. Phi supervises recovery instead, bounded and
        // observable — so a silent migration onto the built-in speakers can no
        // longer happen behind `current`'s back.
        expect(gateway.autoReconnectOn, isFalse);
        expect(coordinator.current, const AudioSettings());
        expect(coordinator.recovery.retrying, isFalse);
        expect(notices, isEmpty);
      },
    );

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
      // Two things get said, in this order, and both are true. Boot says the
      // engine enumerated nothing — which, since the list is built once and
      // never refreshed (issue #412), is a restart-level fact rather than
      // something to retry. Then the stored device reports itself missing.
      expect(notices.map((n) => n.kind), <AudioNoticeKind>[
        AudioNoticeKind.noAudioDevice,
        AudioNoticeKind.switchReverted,
      ]);
      expect(notices.first.message, contains('restart Phi'));
      expect(notices.last.message, contains('no audio output device is open'));
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

    test('a missing target with the open device just gone asks the engine — '
        'neither current nor the notice names a device that is not there '
        '(#416)', () {
      const alpha = AudioDeviceDescriptor(
        name: 'Alpha',
        hostName: 'WASAPI',
        sampleRates: [48000.0],
        bufferSizes: [256],
        defaultBufferSize: 256,
        outputLatency: 256,
      );
      gateway.devices = const [alpha];
      applyStored(
        const AudioSettings(outputHost: 'WASAPI', outputDevice: 'Alpha'),
      );
      expect(coordinator.current?.outputDevice, 'Alpha');
      notices.clear();

      // Alpha is pulled out *between telemetry ticks*: the engine is already on
      // nothing, but no `observeLiveState` has run yet, so [current] still
      // names Alpha — the one moment where the two disagree.
      gateway.devices = const [];
      expect(gateway.activeAudioState(), AudioDeviceState.none);

      // A switch to a device that was never enumerated — a hand-edited
      // settings file, or a preference carried over from another machine —
      // takes the missing-target exit before any open is attempted.
      final ok = coordinator.switchTo(
        const AudioSettings(outputHost: 'ASIO', outputDevice: 'Ghost'),
      );

      expect(ok, isFalse);
      // The lie issue #408 closed on the failed-open exit, in the branch it
      // didn't touch: "staying on Alpha" while the engine is on nothing. The
      // exit re-reads the live state first, so message and [current] follow
      // the engine rather than the stale cache.
      expect(coordinator.current, isNull);
      expect(notices.single.kind, AudioNoticeKind.switchReverted);
      expect(
        notices.single.message,
        contains('no audio output device is open'),
      );
      expect(notices.single.message, isNot(contains('Alpha')));
      // …and having learned nothing is open, it arms recovery now instead of
      // leaving the loss for the next tick to discover.
      expect(coordinator.recovery.retrying, isTrue);
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

  group('recovery from a total loss (issue #410)', () {
    // Nothing used to retry after a total loss. libyse's `setAutoReconnect` was
    // credited with it in design §4, but what it really does is reopen
    // `Pa_GetDefaultOutputDevice()` — not the device that went away — on every
    // control tick with no backoff, which is a worse outcome than silence: the
    // set would migrate onto the built-in speakers with `current` none the wiser.
    // So boot turns it off and the coordinator supervises: a bounded run of real
    // re-opens through the gateway, standing down the moment audio is back.
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
    const storedAlpha = AudioSettings(
      outputHost: 'WASAPI',
      outputDevice: 'Alpha',
    );

    /// Boots onto Alpha, then loses every device the way the machine does: the
    /// switch to Beta closes Alpha, Beta refuses, and the revert finds Alpha
    /// unplugged. Leaves the coordinator in a total loss with a run armed.
    void loseEverything() {
      gateway.devices = const [alpha, beta];
      coordinator.boot();
      coordinator.switchTo(storedAlpha);
      expect(coordinator.current?.outputDevice, 'Alpha');

      gateway.unopenableDeviceNames.add('Beta');
      gateway.devices = const [beta];
      coordinator.switchTo(
        const AudioSettings(outputHost: 'ASIO', outputDevice: 'Beta'),
      );
      expect(coordinator.current, isNull);
      notices.clear();
    }

    test('a total loss arms a bounded run rather than sitting silent', () {
      fakeAsync((async) {
        loseEverything();

        expect(coordinator.recovery.retrying, isTrue);
        expect(coordinator.recovery.limit, recoverySchedule.length);
        expect(coordinator.recovery.gaveUp, isFalse);

        // …and it really does stop. Three attempts, then a notice that says
        // recovery is the performer's move now — not an unbounded background
        // loop nobody can see.
        async.elapse(const Duration(seconds: 10));

        expect(coordinator.recovery.retrying, isFalse);
        expect(coordinator.recovery.gaveUp, isTrue);
        expect(coordinator.recovery.attempts, recoverySchedule.length);
        expect(notices.single.kind, AudioNoticeKind.noAudioDevice);
        expect(notices.single.message, contains('3 attempts'));
        expect(notices.single.message, contains('Settings'));

        // Nothing keeps firing after the budget is spent.
        final callsAfterGivingUp = gateway.calls.length;
        async.elapse(const Duration(minutes: 5));
        expect(gateway.calls, hasLength(callsAfterGivingUp));

        coordinator.dispose();
      });
    });

    test('the hardware coming back reopens the device that was asked for and '
        'audio resumes — no manual step', () {
      fakeAsync((async) {
        loseEverything();

        // Beta is what the performer last chose, so Beta is what recovery
        // reaches for; it starts working again between attempts.
        gateway.unopenableDeviceNames.clear();
        gateway.devices = const [alpha, beta];

        async.elapse(const Duration(seconds: 2));

        // A stream is genuinely open again — asserted on the engine's own live
        // state, not on "a retry happened".
        expect(gateway.activeAudioState().sampleRate, 48000);
        expect(gateway.activeAudioState(), isNot(AudioDeviceState.none));
        // And it is the chosen device, not whatever the platform default is.
        expect(coordinator.current?.outputDevice, 'Beta');
        expect(coordinator.current?.outputHost, 'ASIO');
        expect(gateway.openedDevice, beta);
        // The run stood down, quietly — recovery is not a thing to toast about.
        expect(coordinator.recovery.retrying, isFalse);
        expect(coordinator.recovery.gaveUp, isFalse);
        expect(notices, isEmpty);

        // No further attempts once audio is back.
        final callsAfterRecovery = gateway.calls.length;
        async.elapse(const Duration(minutes: 5));
        expect(gateway.calls, hasLength(callsAfterRecovery));

        coordinator.dispose();
      });
    });

    test('it settles for the platform default when the chosen device stays '
        'missing — and says so once (#413)', () {
      fakeAsync((async) {
        loseEverything();

        // Beta — the chosen device — stays refused, but Alpha is plugged back
        // in and is what the platform default now resolves to. Audio matters
        // more than the preference, and the stored choice is untouched, so the
        // performer can go back to Beta whenever it behaves again.
        gateway.devices = const [alpha];
        async.elapse(const Duration(seconds: 2));

        expect(gateway.activeAudioState().sampleRate, 48000);
        expect(gateway.openedDevice, alpha);
        expect(coordinator.current, isNotNull);
        expect(coordinator.current?.outputDevice, isNull); // the default
        expect(coordinator.recovery.retrying, isFalse);

        // The settle is announced (issue #413): the run stands down here and
        // nothing keeps watching for Beta, so without this one notice the chip
        // would go green and the set would finish on the wrong output with
        // nobody told. It names the device that is still missing and points at
        // the one-click way back.
        expect(notices.single.kind, AudioNoticeKind.recoveredOnDefault);
        expect(notices.single.message, contains('default device'));
        expect(notices.single.message, contains('"Beta"'));
        expect(notices.single.message, contains('Settings'));

        // Said once, at the settle — not again on later ticks or runs.
        async.elapse(const Duration(minutes: 5));
        expect(notices, hasLength(1));

        coordinator.dispose();
      });
    });

    test('settling for the default when only the default was ever wanted is '
        'the intended outcome — no notice (#413)', () {
      fakeAsync((async) {
        // The default device is enumerated but held by another process at
        // boot, so the engine comes up device-less and a run is armed with
        // nothing named as intended. When the default frees up, landing on it
        // is exactly what was wanted — announcing a substitution would be
        // noise.
        gateway.devices = const [alpha];
        gateway.unopenableDeviceNames.add('Alpha');
        coordinator.boot();
        expect(coordinator.current, isNull);
        expect(coordinator.recovery.retrying, isTrue);
        notices.clear();

        gateway.unopenableDeviceNames.clear();
        async.elapse(const Duration(seconds: 2));

        expect(gateway.activeAudioState().sampleRate, 48000);
        expect(coordinator.current, const AudioSettings());
        expect(coordinator.recovery.retrying, isFalse);
        expect(notices, isEmpty);

        coordinator.dispose();
      });
    });

    test('a boot that enumerated nothing says so rather than pretending to '
        'reconnect (#412)', () {
      fakeAsync((async) {
        // A machine whose engine came up seeing no hardware at all. This used to
        // arm a run, on the theory that an interface still finishing its
        // enumeration at login would be picked up. It cannot be: libyse fills
        // its device list once, inside `init()`, from a PortAudio table captured
        // at the first `Pa_Initialize()`, and nothing refreshes it in-process —
        // not `closeCurrentDevice()`, not `close()` + `init()`, and there is no
        // exported rescan (dart-yse #51). An empty list stays empty, so every
        // attempt would resolve nothing and the chip would read RECONNECTING for
        // two minutes about hardware that cannot arrive.
        gateway.devices = const [];

        coordinator.boot();

        expect(coordinator.current, isNull);
        expect(coordinator.recovery.retrying, isFalse);
        expect(coordinator.recovery.attempts, 0);
        // The performer is told the one thing that would actually help.
        expect(notices.single.kind, AudioNoticeKind.noAudioDevice);
        expect(notices.single.message, contains('restart Phi'));

        // And nothing runs in the background afterwards.
        final callsAfterBoot = gateway.calls.length;
        async.elapse(const Duration(minutes: 5));
        expect(gateway.calls, hasLength(callsAfterBoot));

        coordinator.dispose();
      });
    });

    test('an interface plugged in after the engine started stays invisible — '
        'no recovery can reach it (#412)', () {
      fakeAsync((async) {
        gateway.devices = const [];
        coordinator.boot();
        notices.clear();

        // The interface finishes enumerating a moment after login. On the fake
        // this used to be enough for recovery to find it; on the engine it is
        // not, because `System.devices` was already built and is never rebuilt.
        gateway.devices = const [alpha];
        async.elapse(const Duration(minutes: 5));

        expect(gateway.audioDevices(), isEmpty);
        expect(coordinator.current, isNull);
        expect(gateway.activeAudioState(), AudioDeviceState.none);

        // Only a fresh process sees it — which is what the boot notice says.
        coordinator.dispose();
      });
    });

    test('an enumerated device is recovered although the list never changes '
        '(#412)', () {
      fakeAsync((async) {
        // The other half of the cache's behaviour, and the half recovery relies
        // on: an unplugged interface *keeps* its entry, with its old index. So
        // the device the performer asked for stays resolvable throughout the
        // loss, every attempt is a real `openDevice` on it, and the one that
        // lands after the cable goes back in brings audio up.
        gateway.devices = const [alpha, beta];
        coordinator.boot();
        coordinator.switchTo(storedAlpha);

        gateway.devices = const [beta]; // Alpha unplugged
        coordinator.observeLiveState();
        expect(coordinator.recovery.retrying, isTrue);
        // The dropdown still offers it, exactly as the shipped app does.
        expect(gateway.audioDevices(), hasLength(2));
        expect(
          gateway.audioDevices().map((d) => d.name),
          containsAll(<String>['Alpha', 'Beta']),
        );

        gateway.devices = const [alpha, beta]; // plugged back in
        async.elapse(const Duration(seconds: 2));

        expect(gateway.activeAudioState().sampleRate, 48000);
        expect(coordinator.current?.outputDevice, 'Alpha');
        expect(coordinator.recovery.retrying, isFalse);

        coordinator.dispose();
      });
    });

    test('a manual pick that fails re-arms with a fresh budget', () {
      fakeAsync((async) {
        loseEverything();
        async.elapse(const Duration(seconds: 10)); // budget spent
        expect(coordinator.recovery.gaveUp, isTrue);
        notices.clear();

        // The performer tries a device by hand from the settings window. It
        // fails too — but a deliberate act deserves another go, so the run is
        // armed again from attempt one rather than staying given up.
        coordinator.switchTo(
          const AudioSettings(outputHost: 'ASIO', outputDevice: 'Ghost'),
        );

        expect(coordinator.recovery.retrying, isTrue);
        expect(coordinator.recovery.gaveUp, isFalse);
        expect(coordinator.recovery.attempts, 0);

        // And it is bounded again, not endless.
        async.elapse(const Duration(seconds: 10));
        expect(coordinator.recovery.gaveUp, isTrue);

        coordinator.dispose();
      });
    });

    test('a device open by hand stands the run down', () {
      fakeAsync((async) {
        loseEverything();
        expect(coordinator.recovery.retrying, isTrue);

        gateway.unopenableDeviceNames.clear();
        gateway.devices = const [alpha, beta];
        final ok = coordinator.switchTo(storedAlpha);

        expect(ok, isTrue);
        expect(coordinator.recovery.retrying, isFalse);
        expect(coordinator.recovery.attempts, 0);

        // The supervisor does not keep poking a device the performer just fixed.
        final callsAfterFix = gateway.calls.length;
        async.elapse(const Duration(minutes: 5));
        expect(gateway.calls, hasLength(callsAfterFix));

        coordinator.dispose();
      });
    });

    test('an interface unplugged mid-set is noticed on the tick and recovered', () {
      fakeAsync((async) {
        gateway.devices = const [alpha, beta];
        coordinator.boot();
        coordinator.switchTo(storedAlpha);
        expect(coordinator.current?.outputDevice, 'Alpha');
        notices.clear();

        // The cable comes out. Nothing calls `switchTo` — this is the loss the
        // performer actually has, and before issue #410 nothing looked for it:
        // libyse has no device-change event, so the telemetry tick is the only
        // place it can be seen.
        gateway.devices = const [];
        expect(gateway.activeAudioState(), AudioDeviceState.none);

        coordinator.observeLiveState();

        expect(coordinator.current, isNull);
        expect(coordinator.recovery.retrying, isTrue);
        // No notice: the shell's health monitor already says "dropped —
        // reconnecting" at warning level, and an error-level "no audio device"
        // for a state that is being actively retried is exactly the muddle this
        // issue set out to remove. The error comes on the give-up or not at all.
        expect(notices, isEmpty);

        // A standing loss re-arms nothing — the tick runs sixty times a second.
        for (var i = 0; i < 20; i++) {
          coordinator.observeLiveState();
        }
        expect(notices, isEmpty);
        expect(coordinator.recovery.attempts, 0);

        // Plugged back in: the run brings Alpha back with no manual step.
        gateway.devices = const [alpha, beta];
        async.elapse(const Duration(seconds: 2));

        expect(gateway.activeAudioState().sampleRate, 48000);
        expect(coordinator.current?.outputDevice, 'Alpha');
        expect(coordinator.recovery.retrying, isFalse);

        // …and the watch is live again for the next unplug.
        gateway.devices = const [];
        coordinator.observeLiveState();
        expect(coordinator.recovery.retrying, isTrue);

        coordinator.dispose();
      });
    });

    test('the tick says nothing while a device is happily open', () {
      gateway.devices = const [alpha];
      coordinator.boot();
      notices.clear();

      for (var i = 0; i < 20; i++) {
        coordinator.observeLiveState();
      }

      expect(notices, isEmpty);
      expect(coordinator.recovery.retrying, isFalse);
      expect(coordinator.current, isNotNull);
    });

    test('a recovery attempt raises no rate / buffer notices', () {
      fakeAsync((async) {
        gateway.devices = const [alpha];
        coordinator.boot();
        // A stored rate this device does not support: the switch says so once…
        coordinator.switchTo(
          const AudioSettings(
            outputHost: 'WASAPI',
            outputDevice: 'Alpha',
            sampleRate: 96000,
          ),
        );
        expect(
          notices.map((n) => n.kind),
          contains(AudioNoticeKind.unsupportedSampleRate),
        );

        gateway.devices = const [];
        coordinator.switchTo(const AudioSettings(outputDevice: 'Ghost'));
        notices.clear();
        gateway.devices = const [alpha];

        async.elapse(const Duration(seconds: 10));

        // …and the retries that follow say it no more times. Eight repetitions
        // of a rate warning would bury the one message that matters.
        expect(
          notices.map((n) => n.kind),
          isNot(contains(AudioNoticeKind.unsupportedSampleRate)),
        );

        coordinator.dispose();
      });
    });
  });
}
