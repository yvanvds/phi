import 'patch_args.dart';
import 'slider_range.dart';

/// A `.multislider`'s creation arguments, `size minimum maximum` (issue #472).
///
/// [size] is the bank the object is *built* with — a list of another length
/// changes the live count afterwards, which the body reads from the GUI value
/// rather than from here. It is clamped to the engine's 1–1024 and defaults to
/// 8, as `gMultiSlider` does.
class MultisliderArgs {
  const MultisliderArgs({required this.size, required this.range});

  /// Parse [args]. A missing or unparseable argument keeps its engine default.
  factory MultisliderArgs.parse(String args) {
    final parts = splitPatchArgs(args);
    final asked = parts.isEmpty ? null : num.tryParse(parts.first);
    return MultisliderArgs(
      size: asked == null ? defaultSize : asked.truncate().clamp(1, maxSize),
      range: SliderRange.fromArgs(args, at: 1),
    );
  }

  /// The engine's default bank size.
  static const int defaultSize = 8;

  /// The most cells a bank can hold (`gMultiSlider::MAX_CELLS`).
  static const int maxSize = 1024;

  /// How many cells the bank is built with.
  final int size;

  /// The span every cell is clamped into.
  final SliderRange range;
}
