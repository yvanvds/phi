import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/audio_device_state.dart';

/// The live device read-back the diagnostics section shows (design §4).
void main() {
  group('AudioDeviceState', () {
    test('none is all-zero — the "no device open" snapshot', () {
      expect(AudioDeviceState.none.sampleRate, 0);
      expect(AudioDeviceState.none.bufferSize, 0);
      expect(AudioDeviceState.none.outputLatency, 0);
      expect(AudioDeviceState.none.outputLatencyMs, 0);
    });

    test('outputLatencyMs converts samples to ms against the sample rate', () {
      const state = AudioDeviceState(
        sampleRate: 48000,
        bufferSize: 256,
        outputLatency: 256,
      );
      // 256 samples / 48000 Hz * 1000 = 5.333... ms
      expect(state.outputLatencyMs, closeTo(5.333, 1e-3));
    });

    test('outputLatencyMs is zero when the sample rate is unknown', () {
      const state = AudioDeviceState(outputLatency: 256);
      expect(state.outputLatencyMs, 0);
    });

    test('equal when sample rate, buffer, and latency all match', () {
      const a = AudioDeviceState(
        sampleRate: 48000,
        bufferSize: 128,
        outputLatency: 64,
      );
      const b = AudioDeviceState(
        sampleRate: 48000,
        bufferSize: 128,
        outputLatency: 64,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('differing fields break equality', () {
      const a = AudioDeviceState(sampleRate: 48000, bufferSize: 128);
      const b = AudioDeviceState(sampleRate: 44100, bufferSize: 128);
      expect(a, isNot(equals(b)));
    });
  });
}
