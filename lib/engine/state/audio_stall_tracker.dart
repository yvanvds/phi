import 'dart:math' as math;

/// Turns the engine's raw **device-stall gauge** into the session drop count the
/// status strip shows (issue #350).
///
/// ## What the gauge actually is
///
/// `YSE::system::missedCallbacks()` — read through
/// [YseGateway.deviceStallTicks] — is **not** a tally of audio callbacks that
/// missed their deadline, and it is **not** cumulative. Every engine control
/// tick (`system::update`, which Phi drives every [updateInterval]) asks the
/// device manager how many audio callbacks fired since the previous tick. A tick
/// that sees *zero* bumps the gauge; the very next tick that sees one resets it
/// to `0`. So the value reads:
///
/// > how many **consecutive** control ticks in a row saw no audio callback
///
/// — a device-stall gauge, which is also what the engine's own auto-reconnect
/// watches.
///
/// ## Why it can't be shown raw
///
/// Phi drives that control tick every 16 ms, which is *faster* than the audio
/// callback period at any buffer of roughly 768 frames or more. Some ticks then
/// necessarily land between two callbacks and read `1` on a perfectly healthy
/// device; ordinary control-timer jitter does the same at smaller buffers. That
/// is exactly the ~once-a-second `DROPS 1` flicker issue #350 reports.
///
/// ## What this tracker does instead
///
/// * **Threshold** ([stallThreshold]) — a run of empty ticks only counts once it
///   spans more wall-clock time than the device could legitimately be silent, so
///   a normal inter-callback gap can never trip it.
/// * **Latching** — it counts stall *events* (`quiet → stalled` transitions)
///   cumulatively over the session instead of echoing the instantaneous gauge,
///   mirroring the engine's own `Demo22_MissedCallbacks` harness (cumulative
///   transitions plus a peak).
///
/// Pure Dart, no engine or Flutter types: [sample] is fed one gauge reading per
/// telemetry tick and everything else is derived, so the whole interpretation is
/// unit-testable against a synthetic tick sequence.
class AudioStallTracker {
  /// Builds a tracker for a control loop running at [updateInterval] — the
  /// period the raw gauge counts in. Must match the interval actually passed to
  /// `YseGateway.startUpdateTimer`, or the derived threshold is meaningless.
  AudioStallTracker({this.updateInterval = defaultUpdateInterval});

  /// Phi's default engine control-tick period (`PhiEngine.engineUpdateInterval`).
  static const Duration defaultUpdateInterval = Duration(milliseconds: 16);

  /// Floor on [stallThreshold], in control ticks.
  ///
  /// At small buffers the callback period is well under one control tick, so the
  /// derived threshold would collapse to `1` — the very value a healthy device
  /// produces from timer jitter alone. Three ticks (≈48 ms at the default
  /// interval) is the shortest silence worth calling a stall: long enough that
  /// no scheduling hiccup can fake it, short enough to stay far below the
  /// engine's auto-reconnect delay.
  static const int minimumStallTicks = 3;

  /// The control-tick period the gauge counts in.
  final Duration updateInterval;

  int _stalls = 0;
  int _peakTicks = 0;
  int _ticks = 0;
  bool _stalled = false;

  /// Cumulative number of stall **events** since the last [reset] — one per
  /// `quiet → stalled` transition. A stall that persists across many telemetry
  /// samples still counts exactly once. This is the number `DROPS` shows.
  int get stalls => _stalls;

  /// The raw gauge as of the most recent [sample] — consecutive control ticks
  /// with no audio callback. Diagnostics detail, not a user-facing drop count.
  int get ticks => _ticks;

  /// The highest [ticks] value seen since the last [reset] — the "how bad did it
  /// get" companion to [stalls], as the engine demo reports it.
  int get peakTicks => _peakTicks;

  /// Whether the most recent [sample] was inside a stall. Used to latch [stalls]
  /// on the leading edge only.
  bool get stalled => _stalled;

  /// The number of consecutive empty control ticks that counts as a real stall
  /// for a device running at [sampleRate] Hz with [bufferSize] frames per
  /// callback.
  ///
  /// The device is legitimately silent for at most one callback period `P =
  /// bufferSize / sampleRate` between callbacks, so a run only becomes a stall
  /// once it covers **twice** that — one period of genuine silence plus one
  /// period of headroom for control-timer jitter. Converted to ticks that is
  /// `ceil(2 * P / updateInterval)`, never below [minimumStallTicks].
  ///
  /// Falls back to [minimumStallTicks] when no device is open (either value
  /// `0`), so a closed device can't be reported as stalling on arithmetic alone.
  int stallThreshold({required double sampleRate, required int bufferSize}) {
    final tickUs = updateInterval.inMicroseconds;
    if (tickUs <= 0 || sampleRate <= 0 || bufferSize <= 0) {
      return minimumStallTicks;
    }
    final callbackUs = bufferSize / sampleRate * Duration.microsecondsPerSecond;
    final ticks = (2 * callbackUs / tickUs).ceil();
    return math.max(minimumStallTicks, ticks);
  }

  /// Fold one telemetry reading in: [deviceStallTicks] is the raw gauge, and
  /// [sampleRate] / [bufferSize] describe the device it was read from (they may
  /// change mid-session on a device swap, which re-derives the threshold).
  ///
  /// Increments [stalls] only on the leading edge of a stall, so a sustained one
  /// is never re-counted while it persists.
  void sample({
    required int deviceStallTicks,
    required double sampleRate,
    required int bufferSize,
  }) {
    final ticks = math.max(0, deviceStallTicks);
    _ticks = ticks;
    if (ticks > _peakTicks) _peakTicks = ticks;
    final stalled =
        ticks >= stallThreshold(sampleRate: sampleRate, bufferSize: bufferSize);
    if (stalled && !_stalled) _stalls++;
    _stalled = stalled;
  }

  /// Clear every accumulated value — called when the engine starts, so the count
  /// is scoped to the running session rather than the process.
  void reset() {
    _stalls = 0;
    _peakTicks = 0;
    _ticks = 0;
    _stalled = false;
  }
}
