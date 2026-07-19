import 'package:flutter/foundation.dart';

/// A single channel as the Mix surface sees it: a YSE channel id plus the
/// mixer-console state (name, voice swatch, mute, solo, user-set volume,
/// most recent peak reading) that YSE itself does not model.
///
/// Driven exclusively by [PhiEngine] — widgets read from it and call
/// `engine.setChannel*` to mutate. Solo and mute are not native YSE
/// concepts; the engine collapses them into an effective volume before
/// forwarding to the gateway.
class MixerChannel extends ChangeNotifier {
  MixerChannel.master()
    : id = _masterId,
      name = 'master',
      voice = 1,
      isMaster = true;

  MixerChannel.user({required this.id, required this.name, required this.voice})
    : isMaster = false;

  static const int _masterId = -1;

  /// Gateway-level channel id. `-1` denotes the master channel and must not
  /// be passed to per-channel gateway calls.
  final int id;

  /// Visible name — the channel's registry address leaf (the one-name
  /// re-alignment, issue #166). Set at creation; a rename rematerialises the
  /// channel from the moved entity rather than mutating this in place.
  final String name;

  /// Voice swatch index in `[1, 6]`, picked when the channel is added.
  int voice;

  final bool isMaster;

  bool _muted = false;
  bool _soloed = false;
  double _volume = 1.0;
  double _peak = 0.0;
  List<double> _outputPeaks = const [];

  bool get muted => _muted;
  bool get soloed => _soloed;

  /// User-set volume in `[0.0, 1.0]`. The engine may apply a different
  /// *effective* volume to the gateway when mute or solo are active —
  /// this getter always reports what the user dialled in.
  double get volume => _volume;

  /// Most recent post-volume peak in `[0.0, 1.0+]`.
  double get peak => _peak;

  /// Most recent **per speaker output** post-fader peaks, one entry per output
  /// (design `docs/design/mix.md` §6). Empty for an ordinary strip — only the
  /// master is layout-metered, so only its per-output bars are populated. The
  /// length *is* the live output count, so it tracks a device/layout swap
  /// without a restart. Values are linear `[0.0, 1.0+]`.
  List<double> get outputPeaks => _outputPeaks;

  // Internal mutators — only the engine should call these.

  void applyMuted(bool value) {
    if (_muted == value) return;
    _muted = value;
    notifyListeners();
  }

  void applySoloed(bool value) {
    if (_soloed == value) return;
    _soloed = value;
    notifyListeners();
  }

  void applyVolume(double value) {
    if (_volume == value) return;
    _volume = value;
    notifyListeners();
  }

  /// Telemetry-driven. Skips notification when the change is small to keep
  /// the strip widgets from rebuilding every tick at idle.
  void applyPeak(double value) {
    if ((value - _peak).abs() < 0.001) return;
    _peak = value;
    notifyListeners();
  }

  /// Telemetry-driven per-output peaks (design §6). Notifies whenever the
  /// **count** changes — so a layout swap re-renders the master's meter bars
  /// live — or any output moves by a perceptible amount, while skipping the
  /// sub-threshold jitter that would otherwise rebuild the strip every tick at
  /// idle (mirrors [applyPeak]).
  void applyOutputPeaks(List<double> values) {
    if (_outputPeaks.length == values.length) {
      var changed = false;
      for (var i = 0; i < values.length; i++) {
        if ((values[i] - _outputPeaks[i]).abs() >= 0.001) {
          changed = true;
          break;
        }
      }
      if (!changed) return;
    }
    _outputPeaks = List<double>.unmodifiable(values);
    notifyListeners();
  }
}
