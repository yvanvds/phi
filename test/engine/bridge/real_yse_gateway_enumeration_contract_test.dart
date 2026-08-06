import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/audio_device_exception.dart';
import 'package:phi/engine/bridge/real_yse_gateway.dart';

/// Holds **libyse itself** — not the fake — to the device-enumeration contract
/// the boot path is built on (issue #403).
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

  test('initOffline() leaves the engine with no devices to resolve against; '
      'init() is what enumerates', () {
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

    // A second init does not repair it — `system::initShared()` early-returns
    // while the engine is active, so there is no "enumerate later" escape.
    gateway.init();
    expect(
      gateway.audioDevices(),
      isEmpty,
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
    // …so the list phi resolves a stored device against exists only because
    // `init()` opened a device. Every descriptor is usable as an identity
    // (name + host), which is what the coordinator matches on.
    expect(enumerated.every((d) => d.name.isNotEmpty), isTrue);
    expect(enumerated.every((d) => d.hostName.isNotEmpty), isTrue);
  });

  test('a refused open is reported as a failure, not as success', () {
    if (!engineAvailable) {
      markTestSkipped(
        'libyse is not loadable here — engine contract unchecked',
      );
      return;
    }

    // The engine reports a refused `openDevice` to its log and returns
    // `YSE_OK` regardless (dart-yse #52), so `RealYseGateway` confirms the open
    // by reading the live state back. Without that, the device rules (design
    // §5) never see a failure to fall back from: `switchTo` would record a
    // device that is not playing and the app would sit silent believing it had
    // audio.
    //
    // The reproducer needs a device the engine will refuse. The session sample
    // rate is locked at `init()` (dart-yse #53), so any device that does not
    // report that rate is one: `Pa_OpenStream` fails and nothing opens.
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
