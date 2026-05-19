import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Cross-fade controller that drives a `[0.0, 1.0]` intensity value down
/// to zero over a fixed duration. The editor view paints a fuchsia tint
/// across the just-evaluated lines, scaled by [intensity]; the projected
/// view consumes the same controller and highlights the same range.
///
/// Backed by a `Ticker` rather than an `AnimationController` so the
/// controller doesn't need a `TickerProvider` and can live outside the
/// widget tree (a stateful surface owns one, both view widgets read it).
class CodeEvalFlash with ChangeNotifier {
  CodeEvalFlash({Duration? duration})
    : _duration = duration ?? const Duration(milliseconds: 480) {
    _ticker = Ticker(_onTick);
  }

  final Duration _duration;
  late final Ticker _ticker;

  int _startLine = 0;
  int _endLine = -1;
  double _intensity = 0;

  /// First line of the most recently flashed block (inclusive, zero-indexed).
  int get startLine => _startLine;

  /// Last line of the most recently flashed block (inclusive).
  int get endLine => _endLine;

  /// `1.0` immediately after [fire], decaying linearly to `0.0` over
  /// `duration`. Never negative.
  double get intensity => _intensity;

  /// Whether [line] falls inside the most recently flashed block range.
  bool covers(int line) => line >= _startLine && line <= _endLine;

  /// Trigger a flash on `[startLine, endLine]` (both inclusive). Replaces
  /// any in-progress flash.
  void fire({required int startLine, required int endLine}) {
    _startLine = startLine;
    _endLine = endLine;
    _intensity = 1.0;
    if (_ticker.isActive) _ticker.stop();
    _ticker.start();
    notifyListeners();
  }

  void _onTick(Duration elapsed) {
    final progress = (elapsed.inMicroseconds / _duration.inMicroseconds).clamp(
      0.0,
      1.0,
    );
    _intensity = 1.0 - progress;
    if (progress >= 1.0) {
      _ticker.stop();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
