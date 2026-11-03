import 'package:flutter/painting.dart';

import '../../design/tokens/phi_colors.dart';
import '../../domain/system_load/system_load_level.dart';

/// The colour each [SystemLoadLevel] reads as — shared by the chip's dot and
/// the popover's bars so the two always agree.
abstract final class SystemLoadColours {
  /// The colour for [level]: green with headroom, amber busy, red saturated,
  /// muted before the first window.
  static Color forLevel(SystemLoadLevel level) => switch (level) {
    SystemLoadLevel.unknown => PhiColors.fg4,
    SystemLoadLevel.ok => PhiColors.voice4,
    SystemLoadLevel.busy => PhiColors.warm,
    SystemLoadLevel.saturated => PhiColors.hot,
  };
}
