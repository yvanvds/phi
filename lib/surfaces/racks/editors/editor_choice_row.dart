import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../design/widgets/select/phi_select.dart';
import '../../../design/widgets/select/phi_select_option.dart';

/// A labelled enum picker built on the design system's [PhiSelect] — the
/// "selects from the design system" the VA / LFO panels use for waveform and
/// LFO-type choices (design `docs/design/racks-and-voices.md` §8).
///
/// A discrete edit: picking an option commits it straight away through
/// [onChanged] (one journaled edit). Generic over the choice type [T] so it
/// serves any enum.
class EditorChoiceRow<T> extends StatelessWidget {
  const EditorChoiceRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final String label;
  final T value;

  /// The selectable `(value, label)` pairs, in display order.
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: PhiType.monoS().copyWith(color: PhiColors.fg1),
            ),
          ),
          SizedBox(
            width: 128,
            child: PhiSelect<T>.flat(
              value: value,
              options: [
                for (final (v, l) in options)
                  PhiSelectOption<T>(value: v, label: l),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
