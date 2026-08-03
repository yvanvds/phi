import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/state/audio_stall_tracker.dart';

/// Interpretation of the engine's raw device-stall gauge (issue #350).
///
/// The gauge counts *consecutive engine control ticks that saw no audio
/// callback*, so at Phi's 16 ms tick a healthy device produces isolated `1`s —
/// which the `DROPS` chip used to render as real drops. These tests drive
/// synthetic tick sequences straight through the tracker: isolated blips must
/// never count, a sustained run must count exactly once, and the threshold that
/// separates the two must follow the device's own callback period.
void main() {
  // 48 kHz devices at the buffer sizes the flicker was reported around.
  const rate = 48000.0;

  AudioStallTracker tracker({
    Duration interval = AudioStallTracker.defaultUpdateInterval,
  }) => AudioStallTracker(updateInterval: interval);

  void feed(
    AudioStallTracker t,
    List<int> gauges, {
    double sampleRate = rate,
    int bufferSize = 1024,
  }) {
    for (final gauge in gauges) {
      t.sample(
        deviceStallTicks: gauge,
        sampleRate: sampleRate,
        bufferSize: bufferSize,
      );
    }
  }

  group('stallThreshold', () {
    test('never drops below the minimum, however small the buffer', () {
      final t = tracker();
      // 128 frames @ 48 kHz ≈ 2.7 ms — far under one 16 ms control tick, so the
      // derived value would be 1 (the very reading a healthy device produces).
      expect(
        t.stallThreshold(sampleRate: rate, bufferSize: 128),
        AudioStallTracker.minimumStallTicks,
      );
      expect(
        t.stallThreshold(sampleRate: rate, bufferSize: 512),
        AudioStallTracker.minimumStallTicks,
      );
    });

    test('scales with the callback period at large buffers', () {
      final t = tracker();
      // 1024 @ 48 kHz ≈ 21.3 ms → 2 × 21.3 / 16 = 2.67 → 3 ticks.
      expect(t.stallThreshold(sampleRate: rate, bufferSize: 1024), 3);
      // 2048 @ 48 kHz ≈ 42.7 ms → 2 × 42.7 / 16 = 5.33 → 6 ticks.
      expect(t.stallThreshold(sampleRate: rate, bufferSize: 2048), 6);
      // 4096 @ 44.1 kHz ≈ 92.9 ms → 2 × 92.9 / 16 = 11.6 → 12 ticks.
      expect(t.stallThreshold(sampleRate: 44100, bufferSize: 4096), 12);
    });

    test('follows the control-tick period it was built with', () {
      // The engine demo's 100 ms cadence swallows the same callback period
      // whole, so its threshold is the floor rather than a scaled value.
      final slow = tracker(interval: const Duration(milliseconds: 100));
      expect(
        slow.stallThreshold(sampleRate: rate, bufferSize: 1024),
        AudioStallTracker.minimumStallTicks,
      );
      // A faster tick needs proportionally more of them to cover the same gap.
      final fast = tracker(interval: const Duration(milliseconds: 4));
      expect(fast.stallThreshold(sampleRate: rate, bufferSize: 1024), 11);
    });

    test('falls back to the minimum when no device is open', () {
      final t = tracker();
      expect(
        t.stallThreshold(sampleRate: 0, bufferSize: 0),
        AudioStallTracker.minimumStallTicks,
      );
      expect(
        t.stallThreshold(sampleRate: rate, bufferSize: 0),
        AudioStallTracker.minimumStallTicks,
      );
    });
  });

  group('stall counting', () {
    test('isolated gauge blips are not drops — the issue #350 regression', () {
      final t = tracker();
      // The reported idle pattern: a lone `1` every so often, cleared by the
      // next tick that sees a callback. Nothing here is a dropout.
      feed(t, [0, 1, 0, 0, 1, 0, 1, 0, 0, 0, 1, 0]);

      expect(t.stalls, 0);
      expect(t.stalled, isFalse);
      // The raw gauge is still reported for diagnostics, just not as a drop.
      expect(t.peakTicks, 1);
    });

    test('a run just short of the threshold still does not count', () {
      final t = tracker();
      // Threshold is 3 at 1024 frames; a run peaking at 2 stays quiet.
      feed(t, [0, 1, 2, 0, 1, 2, 0]);

      expect(t.stalls, 0);
      expect(t.peakTicks, 2);
    });

    test('a sustained run counts exactly once and does not re-count', () {
      final t = tracker();
      feed(t, [0, 1, 2]);
      expect(t.stalls, 0);

      // Crossing the threshold latches one event …
      feed(t, [3]);
      expect(t.stalls, 1);
      expect(t.stalled, isTrue);

      // … and staying stalled — however long, however deep — adds nothing.
      feed(t, [4, 7, 12, 40, 41]);
      expect(t.stalls, 1);
      expect(t.peakTicks, 41);
    });

    test('the device recovering re-arms the latch for the next stall', () {
      final t = tracker();
      feed(t, [5, 6]); // stall one
      expect(t.stalls, 1);

      feed(t, [0, 1, 0]); // recovered, with the usual healthy blip
      expect(t.stalled, isFalse);
      expect(t.stalls, 1);

      feed(t, [4]); // stall two
      expect(t.stalls, 2);
    });

    test('a sample can jump the threshold in one step', () {
      // Telemetry polls every 50 ms while the gauge counts 16 ms ticks, so a
      // reading can skip intermediate values — the edge must still be caught.
      final t = tracker();
      feed(t, [0, 9]);
      expect(t.stalls, 1);
    });

    test('a large buffer needs a longer run than a small one', () {
      // The same gauge reading of 4 is a stall at 512 frames (threshold 3) but
      // not yet at 2048 (threshold 6) — the whole point of deriving it.
      final small = tracker();
      feed(small, [4], bufferSize: 512);
      expect(small.stalls, 1);

      final large = tracker();
      feed(large, [4], bufferSize: 2048);
      expect(large.stalls, 0);
    });

    test('a device swap re-derives the threshold mid-session', () {
      final t = tracker();
      // At 2048 frames a gauge of 4 is within the normal inter-callback gap.
      feed(t, [4], bufferSize: 2048);
      expect(t.stalls, 0);

      // The performer switches to a 256-frame device; the same reading is now
      // far past what that device could legitimately be silent for.
      feed(t, [4], bufferSize: 256);
      expect(t.stalls, 1);
    });

    test('no device open uses the floor rather than counting everything', () {
      final t = tracker();
      feed(t, [1, 2], sampleRate: 0, bufferSize: 0);
      expect(t.stalls, 0);
      feed(t, [3], sampleRate: 0, bufferSize: 0);
      expect(t.stalls, 1);
    });

    test('a negative gauge reading is clamped, never counted', () {
      final t = tracker();
      feed(t, [-1, -5]);
      expect(t.stalls, 0);
      expect(t.ticks, 0);
      expect(t.peakTicks, 0);
    });

    test('reset clears the session so a restart begins at zero', () {
      final t = tracker();
      feed(t, [8, 9]);
      expect(t.stalls, 1);
      expect(t.peakTicks, 9);

      t.reset();

      expect(t.stalls, 0);
      expect(t.ticks, 0);
      expect(t.peakTicks, 0);
      expect(t.stalled, isFalse);
      // The latch is re-armed too: the next stall counts again.
      feed(t, [8]);
      expect(t.stalls, 1);
    });
  });
}
