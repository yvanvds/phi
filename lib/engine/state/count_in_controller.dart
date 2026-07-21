import 'package:flutter/foundation.dart';

/// Count-in against the engine clock (issue #263, design
/// `docs/design/midi-recording.md` §5).
///
/// A [ChangeNotifier] the toolbar count-in setting binds to. It holds the
/// **count length** in bars (`0 / 1 / 2` — performance state, never persisted)
/// and schedules the delay before play (and record) begin: [begin] captures the
/// current engine-clock beat as the origin and completes once the clock has
/// advanced `bars × beatsPerBar` beats, firing the downbeat callback. The
/// schedule is a **query of the engine clock** each frame ([tick]) — no Dart
/// timer sits in the timing path, so the downbeat lands on the clock's beat, not
/// on a wall-clock accumulator that jitters under UI-isolate load.
///
/// The controller is audio-agnostic: whether the count is *heard* (the click
/// counting) or a **silent wait** is the metronome's concern — the same schedule
/// runs either way (design §5). Aborting mid-count ([cancel]) fires nothing, so
/// a stop during the count starts nothing; and because only a fresh play is
/// scheduled, a punch-in into an already-running session never engages a count.
class CountInController extends ChangeNotifier {
  CountInController({int bars = 0}) : _bars = bars.clamp(0, maxBars);

  /// The largest count-in the setting offers — two bars (design §5).
  static const int maxBars = 2;

  int _bars;

  /// The count length in bars, in `0..maxBars`. `0` disables the count so play
  /// and record start at once. Performance state; never persisted.
  int get bars => _bars;
  set bars(int value) {
    final next = value.clamp(0, maxBars);
    if (_bars == next) return;
    _bars = next;
    notifyListeners();
  }

  bool _counting = false;
  double _origin = 0;
  double _targetBeats = 0;
  double Function()? _beatPosition;
  VoidCallback? _onComplete;

  /// Whether a count is in progress — play waits on it, and the engine's frame
  /// ticker keeps spinning to [tick] it toward the downbeat.
  bool get isCounting => _counting;

  /// Beats still to elapse before the downbeat, or `0` when no count runs. A live
  /// read of the engine clock, so a count-in display can bind to it.
  double get beatsRemaining {
    if (!_counting) return 0;
    final left = _targetBeats - (_beatPosition!() - _origin);
    return left > 0 ? left : 0;
  }

  /// Begin a count of [bars] bars at [beatsPerBar], measuring elapsed beats
  /// through [beatPosition] — a query of a **running** engine clock. Captures the
  /// clock's current position as the origin, so the count completes when the
  /// clock has advanced `bars × beatsPerBar` beats, at which point [onComplete]
  /// fires exactly once (on the [tick] that crosses the downbeat).
  ///
  /// Returns `false` — scheduling nothing and never firing [onComplete] — when
  /// there is nothing to wait for ([bars] is `0`, or [beatsPerBar] is
  /// non-positive): the caller then starts immediately. Also `false`, a no-op,
  /// when a count is already running.
  bool begin({
    required int beatsPerBar,
    required double Function() beatPosition,
    required VoidCallback onComplete,
  }) {
    if (_counting || _bars <= 0 || beatsPerBar <= 0) return false;
    _counting = true;
    _beatPosition = beatPosition;
    _origin = beatPosition();
    _targetBeats = _bars * beatsPerBar.toDouble();
    _onComplete = onComplete;
    notifyListeners();
    return true;
  }

  /// One frame of the engine ticker: if a count is running and the clock has
  /// reached the downbeat, clear the count and fire its completion. A no-op
  /// otherwise. The callback runs *after* the state is cleared, so it may start
  /// playback (and a re-entrant [begin]) against a clean controller.
  void tick() {
    if (!_counting) return;
    final elapsed = _beatPosition!() - _origin;
    // A hair of tolerance so a clock landing a floating-point whisker short of
    // the exact beat still fires on the intended frame rather than the next.
    if (elapsed < _targetBeats - _epsilon) return;
    final done = _onComplete;
    _clear();
    notifyListeners();
    done?.call();
  }

  /// Abort a running count without firing the downbeat — a stop (or pause)
  /// during the count. A no-op when no count is running.
  void cancel() {
    if (!_counting) return;
    _clear();
    notifyListeners();
  }

  void _clear() {
    _counting = false;
    _origin = 0;
    _targetBeats = 0;
    _beatPosition = null;
    _onComplete = null;
  }

  static const double _epsilon = 1e-9;
}
