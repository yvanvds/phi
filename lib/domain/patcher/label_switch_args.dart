import 'patch_args.dart';

/// The creation arguments of a `.led` or a `.textbutton` — an optional leading
/// `momentary` keyword, then the label (issue #470).
///
/// Read the way the engine's `gLabelSwitchBase::ShapeLabel` reads them: the
/// keyword counts only as the first word, and every word after it is the label,
/// joined with single spaces — so `.textbutton filter cutoff` is one control
/// called "filter cutoff".
class LabelSwitchArgs {
  const LabelSwitchArgs({this.momentary = false, this.label = ''});

  factory LabelSwitchArgs.parse(String args) {
    final words = splitPatchArgs(args);
    final momentary = words.isNotEmpty && words.first == keyword;
    return LabelSwitchArgs(
      momentary: momentary,
      label: words.skip(momentary ? 1 : 0).join(' '),
    );
  }

  /// The first-word keyword that makes the control register presses rather
  /// than latch.
  static const String keyword = 'momentary';

  /// Whether an input is a press (lit until the next poll) rather than a state.
  final bool momentary;

  /// The control's name, or `''` for an unlabelled one.
  final String label;
}
