import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/audio_device_descriptor.dart';

/// The FFI-free descriptor the gateway hands out (design §4, §7): a plain value
/// object compared by value, list fields included.
void main() {
  group('AudioDeviceDescriptor', () {
    AudioDeviceDescriptor make({String host = 'WASAPI'}) =>
        AudioDeviceDescriptor(
          name: 'Fireface UCX',
          hostName: host,
          inputChannelNames: const ['In 1', 'In 2'],
          outputChannelNames: const ['Out 1', 'Out 2'],
          sampleRates: const [44100.0, 48000.0],
          bufferSizes: const [128, 256],
          defaultBufferSize: 256,
          outputLatency: 256,
          inputLatency: 256,
        );

    test('only name + host are required; the rest default empty/zero', () {
      const d = AudioDeviceDescriptor(name: 'Bare', hostName: 'ASIO');
      expect(d.inputChannelNames, isEmpty);
      expect(d.outputChannelNames, isEmpty);
      expect(d.sampleRates, isEmpty);
      expect(d.bufferSizes, isEmpty);
      expect(d.defaultBufferSize, 0);
      expect(d.outputLatency, 0);
      expect(d.inputLatency, 0);
    });

    test('equal when every field (lists included) matches', () {
      expect(make(), equals(make()));
      expect(make().hashCode, make().hashCode);
    });

    test('the same device under a different host is a distinct value', () {
      // The name+host identity rule (design §3): WASAPI and ASIO are two choices.
      expect(make(host: 'WASAPI'), isNot(equals(make(host: 'ASIO'))));
    });

    test('differing list contents break equality', () {
      const a = AudioDeviceDescriptor(
        name: 'X',
        hostName: 'H',
        sampleRates: [48000.0],
      );
      const b = AudioDeviceDescriptor(
        name: 'X',
        hostName: 'H',
        sampleRates: [96000.0],
      );
      expect(a, isNot(equals(b)));
    });

    test('toString names the device, host, and channel counts', () {
      expect(
        make().toString(),
        'AudioDeviceDescriptor(Fireface UCX on WASAPI, 2out/2in)',
      );
    });
  });
}
