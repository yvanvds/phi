import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_type.dart';
import '../../tokens/phi_voices.dart';
import 'patch_canvas_constants.dart';

/// The `.radiogroup` object drawn as **only itself**: one row per item, a mark
/// and the item's name, stacked top to bottom (issue #471).
///
/// The mark is a radio button — round, one lit at a time — or with [multi] a
/// check box, square, any number lit. A lit mark fills with the voice colour.
/// Each row takes an equal share of the node's height.
///
/// Visual-only: the press belongs to the caller ([onSelect] reports the item
/// number), so the group stays inert chrome while the canvas is in edit mode
/// (issue #378).
class PatchRadioGroup extends StatelessWidget {
  const PatchRadioGroup({
    required this.labels,
    required this.selected,
    required this.voice,
    this.multi = false,
    this.onSelect,
    super.key,
  });

  /// Every item's name, in order.
  final List<String> labels;

  /// The selected item numbers.
  final Set<int> selected;

  /// Voice index in `[1, 6]`; a lit mark takes its colour.
  final int voice;

  /// Whether the marks are check boxes (several lit) rather than radio buttons.
  final bool multi;

  /// Called with the number of the item whose row was tapped.
  final ValueChanged<int>? onSelect;

  /// Key on item [index]'s row, so a test can tap one item of many.
  static Key itemKey(int index) => Key('PatchRadioGroup.item.$index');

  /// The mark's side as a fraction of a row's height.
  static const double markFraction = 0.55;

  @override
  Widget build(BuildContext context) {
    final color = PhiVoices.color(voice);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        border: Border.all(color: PhiColors.line2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                key: itemKey(i),
                behavior: HitTestBehavior.opaque,
                onTap: onSelect == null ? null : () => onSelect!(i),
                child: _row(labels[i], selected.contains(i), color),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, bool on, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PatchCanvasConstants.objectBoxPaddingH,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mark = constraints.hasBoundedHeight
              ? constraints.maxHeight * markFraction
              : 10.0;
          return Row(
            children: [
              SizedBox.square(
                dimension: mark,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: multi ? BoxShape.rectangle : BoxShape.circle,
                    color: on ? color : PhiColors.bg2,
                    border: Border.all(color: on ? color : PhiColors.line2),
                  ),
                ),
              ),
              const SizedBox(width: PatchCanvasConstants.objectBoxPaddingH),
              Expanded(
                child: Text(
                  label,
                  style: PhiType.monoS().copyWith(
                    color: on ? PhiColors.fg0 : PhiColors.fg1,
                  ),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
