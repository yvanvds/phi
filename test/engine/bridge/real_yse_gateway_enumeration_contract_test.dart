import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/audio_device_exception.dart';
import 'package:phi/engine/bridge/real_yse_gateway.dart';

/// Holds **libyse itself** — not the fake — to the device-enumeration contract
/// the boot and recovery paths are built on (issues #403, #445).
///
/// Why this file exists: the stored-device boot path used `initOffline()` and
/// resolved the stored device against `audioDevices()`. Every test passed,
/// because `FakeYseGateway.initOffline()` handed back its fabricated hardware.
/// The engine hands back nothing — `deviceManager::init(false)` skips both
/// `Pa_Initialize()` and `updateDeviceList()`, and the accessor behind
/// `System.devices` has no lazy refresh — so a real performer with a stored
/// device booted silent. No test written against the double could have caught
/// that; only a test that asks the engine can.
///
/// It runs wherever the native library is loadable (a developer machine, the
/// Windows tiers) and **skips itself** where it is not — CI's Linux
/// analyze+test job checks out `dart-yse` without building the engine, so
/// `flutter test` there sees no `libyse.so`. A skip is honest: the contract is
/// still asserted on every machine that has the engine, which is every machine
/// that could ever run the app.
void main() {
  late RealYseGateway gateway;
  late bool engineAvailable;

  setUpAll(() {
    gateway = RealYseGateway();
    try {
      // Any call touching `System.instance` resolves + loads the library.
      gateway.engineVersion;
      engineAvailable = true;
    } catch (_) {
      engineAvailable = false;
    }
  });

  tearDownAll(() {
    if (engineAvailable) {
      try {
        gateway.close();
      } catch (_) {
        // Closing an engine that never came up is not a test failure.
      }
    }
  });

  test('initOffline() enumerates nothing on its own; refreshDevices() lists '
      'the devices without opening one', () {
    if (!engineAvailable) {
      markTestSkipped(
        'libyse is not loadable here — engine contract unchecked',
      );
      return;
    }

    // ── the invariant, hardware or not ────────────────────────────────────
    // An offline session enumerates nothing. True on a machine with 19 devices
    // and on a bare CI runner alike, which is what makes it assertable here.
    expect(
      gateway.audioDevices(),
      isEmpty,
      reason: 'before any init the engine has not enumerated',
    );

    gateway.initOffline();
    expect(
      gateway.audioDevices(),
      isEmpty,
      reason:
          'initOffline() must not be treated as a device-enumerating boot: '
          'the boot path resolves stored devices against this list',
    );

    // yse 0.2.0's `refreshDevices()` is the enumerate-without-opening call
    // libYSE 2.4 lacked (issue #445): recovery calls it on every attempt, and
    // relies on it never opening a stream behind the coordinator's back.
    final reachable = gateway.refreshDevices();
    expect(
      gateway.activeAudioState().sampleRate,
      0,
      reason: 'refreshDevices() must not open a device',
    );
    if (!reachable) {
      expect(gateway.audioDevices(), isEmpty);
    }
    final refreshed = {
      for (final d in gateway.audioDevices()) '${d.hostName}/${d.name}',
    };

    // A second init does not turn the offline session into a device session —
    // the engine ignores it while active, so nothing opens.
    gateway.init();
    expect(
      gateway.activeAudioState().sampleRate,
      0,
      reason: 'init() after initOffline() is ignored by the engine',
    );

    // ── the other half, where there is hardware ───────────────────────────
    gateway.close();
    gateway.init();
    final enumerated = gateway.audioDevices();
    if (enumerated.isEmpty) {
      // A machine with no audio hardware at all: nothing more to prove, and
      // the invariant above already holds.
      markTestSkipped(
        'no audio devices on this machine — enumeration half '
        'of the contract unchecked',
      );
      return;
    }
    // Every descriptor is usable as an identity (name + host), which is what
    // the coordinator matches on…
    expect(enumerated.every((d) => d.name.isNotEmpty), isTrue);
    expect(enumerated.every((d) => d.hostName.isNotEmpty), isTrue);
    // …and the offline refresh above saw the same machine `init()` did, so a
    // recovery attempt's refresh can resolve whatever a boot could.
    expect(refreshed, {for (final d in enumerated) '${d.hostName}/${d.name}'});
  });

  test('a refused open is reported as a failure, not as success', () {
    if (!engineAvailable) {
      markTestSkipped(
        'libyse is not loadable here — engine contract unchecked',
      );
      return;
    }

    // libYSE 2.4 reported a refused `openDevice` only to its log and returned
    // `YSE_OK` (dart-yse #52), so `RealYseGateway` used to confirm every open
    // by reading `activeSampleRate` back. yse 0.2.0 throws instead, and the
    // read-back is gone (issue #445) — this test is what proves the engine's
    // throw reaches the device rules (design §5) as a failure to fall back
    // from, rather than a silent "success" on a device that is not playing.
    //
    // The reproducer needs a device the engine will refuse. The session sample
    // rate is locked at `init()` (dart-yse #53), so any device that does not
    // report that rate is one: the stream fails to open and nothing opens.
    gateway.init();
    final sessionRate = gateway.activeSampleRate;
    final refusing = gateway
        .audioDevices()
        .where(
          (d) =>
              d.outputChannelNames.isNotEmpty &&
              d.sampleRates.isNotEmpty &&
              !d.sampleRates.contains(sessionRate),
        )
        .firstOrNull;
    if (sessionRate == 0 || refusing == null) {
      markTestSkipped(
        'no device on this machine refuses the session rate '
        '($sessionRate Hz) — silent-refusal detection unchecked',
      );
      return;
    }

    expect(
      () => gateway.openAudioDevice(refusing),
      throwsA(isA<AudioDeviceException>()),
      reason:
          'the engine refused "${refusing.name}" on "${refusing.hostName}" '
          'without raising an error; the bridge must turn that into one',
    );
    // And the read-back agrees with the exception: nothing is open.
    expect(gateway.activeAudioState().sampleRate, 0);
  });
}
