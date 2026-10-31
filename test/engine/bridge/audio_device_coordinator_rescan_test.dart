import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/engine/bridge/audio_device_coordinator.dart';
import 'package:phi/engine/bridge/audio_device_descriptor.dart';
import 'package:phi/engine/bridge/audio_device_notice.dart';

import '../test_doubles/fake_yse_gateway.dart';

/// `AudioDeviceCoordinator.rescanDevices` (issue #450): re-reading the
/// machine's devices while one is playing. PortAudio cannot rescan with a
/// stream open, so the rescan closes the stream, refreshes and reopens the same
/// device — without touching the session or any stored choice.
const _alpha = AudioDeviceDescriptor(
  name: 'Alpha',
  hostName: 'WASAPI',
  sampleRates: [44100.0, 48000.0],
  bufferSizes: [128, 256],
  defaultBufferSize: 256,
  outputLatency: 256,
);
const _beta = AudioDeviceDescriptor(
  name: 'Beta',
  hostName: 'ASIO',
  sampleRates: [48000.0, 96000.0],
  bufferSizes: [64, 128],
  defaultBufferSize: 64,
  outputLatency: 128,
);
const _gamma = AudioDeviceDescriptor(
  name: 'Gamma',
  hostName: 'ASIO',
  sampleRates: [48000.0],
  bufferSizes: [128],
  defaultBufferSize: 128,
  outputLatency: 128,
);

const _onBeta = AudioSettings(
  outputHost: 'ASIO',
  outputDevice: 'Beta',
  bufferSize: 128,
);

void main() {
  late FakeYseGateway gateway;
  late List<AudioDeviceNotice> notices;
  late AudioDeviceCoordinator coordinator;

  setUp(() {
    gateway = FakeYseGateway()..devices = const [_alpha, _beta];
    notices = [];
    coordinator = AudioDeviceCoordinator(
      gateway,
      onNotice: notices.add,
      recoverySchedule: const [Duration(seconds: 1), Duration(seconds: 1)],
    );
  });

  tearDown(() {
    coordinator.dispose();
    return gateway.dispose();
  });

  List<String> names() => gateway.audioDevices().map((d) => d.name).toList();

  test('a refresh alone cannot see hardware plugged in while a device plays '
      '— the gap the rescan closes', () {
    expect(coordinator.boot(_onBeta), isTrue);
    gateway.devices = const [_alpha, _beta, _gamma];
    gateway.refreshDevices();
    expect(names(), isNot(contains('Gamma')));
  });

  test('lists an interface plugged in mid-session and reopens the same '
      'device, settings intact, in the same session', () {
    expect(coordinator.boot(_onBeta), isTrue);
    final rate = gateway.sessionSampleRate;
    gateway.devices = const [_alpha, _beta, _gamma];
    notices.clear();
    gateway.calls.clear();

    expect(coordinator.rescanDevices(), isTrue);

    expect(names(), contains('Gamma'));
    expect(coordinator.current, _onBeta);
    expect(gateway.activeAudioState().bufferSize, 128);
    // Stream closed *before* the refresh (else PortAudio re-reads the stale
    // list), and the session is never closed — nothing built on it is lost.
    expect(gateway.calls.indexOf('closeAudioDevice'), 0);
    expect(gateway.calls.indexOf('refreshDevices'), 1);
    expect(gateway.calls, isNot(contains('close')));
    expect(gateway.sessionSampleRate, rate);
    expect(notices, isEmpty);
  });

  test('drops an unplugged interface from the list', () {
    expect(coordinator.boot(_onBeta), isTrue);
    gateway.devices = const [_beta, _gamma]; // Alpha pulled, Beta still plays
    expect(names(), contains('Alpha'));

    expect(coordinator.rescanDevices(), isTrue);

    expect(names(), isNot(contains('Alpha')));
    expect(coordinator.current?.outputDevice, 'Beta');
  });

  test('when the open device itself is gone it lands on the default with a '
      'notice — and keeps wanting the stored device', () {
    fakeAsync((async) {
      expect(coordinator.boot(_onBeta), isTrue);
      // Beta's stream is gone from the hardware; nothing has noticed yet.
      gateway.devices = const [_alpha];
      notices.clear();

      expect(coordinator.rescanDevices(), isFalse);

      // The platform default (Alpha, first listed) — spelled as no choice.
      expect(coordinator.current, const AudioSettings());
      expect(gateway.openedDevice?.name, 'Alpha');
      expect(notices.single.kind, AudioNoticeKind.switchReverted);
      expect(notices.single.message, contains('"Beta" is no longer available'));
      expect(coordinator.recovery.retrying, isFalse);
      // Beta back: a rescan lists it again but reopens what is open — it
      // changes no choice; re-picking Beta is the performer's move.
      gateway.devices = const [_alpha, _beta];
      expect(coordinator.rescanDevices(), isTrue);
      expect(names(), contains('Beta'));
      expect(coordinator.current, const AudioSettings());
      expect(gateway.openedDevice?.name, 'Alpha');
    });
  });

  test('with every device gone it reports the loss and arms recovery', () {
    fakeAsync((async) {
      expect(coordinator.boot(_onBeta), isTrue);
      gateway.devices = const [];
      notices.clear();

      expect(coordinator.rescanDevices(), isFalse);

      expect(coordinator.current, isNull);
      expect(notices.single.kind, AudioNoticeKind.noAudioDevice);
      expect(coordinator.recovery.retrying, isTrue);

      // Recovery reaches for the device the performer wanted when it returns.
      gateway.devices = const [_alpha, _beta];
      async.elapse(const Duration(seconds: 1));
      expect(coordinator.current?.outputDevice, 'Beta');
      expect(coordinator.recovery.retrying, isFalse);
    });
  });

  test('with nothing open it runs one attempt now — opening the wanted '
      'device if it has arrived — and stands recovery down', () {
    fakeAsync((async) {
      gateway.devices = const [];
      expect(coordinator.boot(_onBeta), isFalse);
      expect(coordinator.recovery.retrying, isTrue);

      // Nothing arrived yet: the rescan opens nothing and the run continues.
      expect(coordinator.rescanDevices(), isFalse);
      expect(coordinator.current, isNull);

      gateway.devices = const [_alpha, _beta];
      expect(coordinator.rescanDevices(), isTrue);

      expect(coordinator.current?.outputDevice, 'Beta');
      expect(coordinator.recovery.retrying, isFalse);
      expect(coordinator.recovery.gaveUp, isFalse);
    });
  });
}
