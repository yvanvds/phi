import 'package:flutter/widgets.dart';

import '../select/phi_select.dart';
import '../select/phi_select_option.dart';

/// The `.umenu` object drawn as **only itself**: a one-line drop-down over the
/// control's item names — a [PhiSelect] in its dense canvas form (issue #471).
///
/// The closed box shows the selected item. With [multi] the list carries a
/// checkmark beside every selected item, stays open while items are toggled,
/// and the closed box lists the selection.
///
/// Visual-only: the pick belongs to the caller ([onSelect] reports the item
/// number), so the menu stays inert chrome while the canvas is in edit mode
/// (issue #378).
class PatchMenuBox extends StatelessWidget {
  const PatchMenuBox({
    required this.labels,
    required this.selected,
    this.multi = false,
    this.onSelect,
    super.key,
  });

  /// Every item's name, in order.
  final List<String> labels;

  /// The selected item numbers.
  final Set<int> selected;

  /// Whether several items can be selected at once.
  final bool multi;

  /// Called with the item number picked from the list.
  final ValueChanged<int>? onSelect;

  /// What the closed box says when nothing is selected.
  static const String nothing = '–';

  @override
  Widget build(BuildContext context) {
    final picked = [
      for (var i = 0; i < labels.length; i++)
        if (selected.contains(i)) labels[i],
    ];
    return PhiSelect<int>.flat(
      dense: true,
      value: multi || selected.isEmpty ? null : selected.first,
      options: [
        for (var i = 0; i < labels.length; i++)
          PhiSelectOption(value: i, label: labels[i]),
      ],
      onChanged: onSelect,
      placeholder: nothing,
      isSelected: selected.contains,
      keepOpenOnSelect: multi,
      displayLabel: multi && picked.isNotEmpty ? picked.join(', ') : null,
    );
  }
}
