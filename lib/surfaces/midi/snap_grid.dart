import '../../design/widgets/select/phi_select_option.dart';

/// The snap-grid choices for the piano roll's header picker (design
/// `docs/design/midi-clips.md` §5), feeding `ClipEditor.gridDivision`.
///
/// Values are in **beats**, with a quarter note = 1 beat: so `1/16` = 0.25 (the
/// painter's finest line) and `off` = 0, which disables snapping so a note lands
/// wherever the pointer is. The triplet values are the exact thirds
/// ([eighthTriplet] = 1/3 beat, [sixteenthTriplet] = 1/6 beat) held as named
/// constants so the picker's selected-value match against `gridDivision` is
/// bit-identical (no `1/3` vs `0.333…` drift).
class SnapGrid {
  const SnapGrid._();

  /// Snapping disabled — add / drag / resize / nudge run free.
  static const double off = 0;
  static const double whole = 4; // 1/1
  static const double half = 2; // 1/2
  static const double quarter = 1; // 1/4
  static const double eighth = 0.5; // 1/8
  static const double sixteenth = 0.25; // 1/16
  static const double thirtySecond = 0.125; // 1/32
  static const double eighthTriplet = 1 / 3; // 1/8T
  static const double sixteenthTriplet = 1 / 6; // 1/16T

  /// The options, in display order, for a `PhiSelect<double>`.
  static const List<PhiSelectOption<double>> options = [
    PhiSelectOption(value: off, label: 'off'),
    PhiSelectOption(value: whole, label: '1/1'),
    PhiSelectOption(value: half, label: '1/2'),
    PhiSelectOption(value: quarter, label: '1/4'),
    PhiSelectOption(value: eighth, label: '1/8'),
    PhiSelectOption(value: sixteenth, label: '1/16'),
    PhiSelectOption(value: thirtySecond, label: '1/32'),
    PhiSelectOption(value: eighthTriplet, label: '1/8T'),
    PhiSelectOption(value: sixteenthTriplet, label: '1/16T'),
  ];
}
