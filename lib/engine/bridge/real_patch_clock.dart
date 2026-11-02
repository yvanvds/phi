import 'package:yse/yse.dart';

import 'patch_clock.dart';

/// Production [PatchClock]: a `package:yse` [DomainClock] (issue #529).
class RealPatchClock implements PatchClock {
  RealPatchClock(this._clock);

  final DomainClock _clock;

  @override
  String get name => _clock.name;

  @override
  void setTempo(double bpm) => _clock.setTempo(bpm);

  @override
  double get beatPosition => _clock.beatPosition;

  @override
  double get currentTempo => _clock.currentTempo;

  @override
  void dispose() => _clock.dispose();
}
