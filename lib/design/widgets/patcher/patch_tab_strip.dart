import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_type.dart';
import '../../tokens/phi_voices.dart';
import 'patch_canvas_constants.dart';

/// The `.tab` object drawn as **only itself**: a row of tabs, one per item,
/// each carrying the item's name (issue #471).
///
/// A selected tab is lit — filled with the voice glow, underlined in the voice
/// colour, its name bright — and with a `multi` control more than one can be.
/// Each tab takes an equal share of the node's width.
///
/// Visual-only: the press belongs to the caller ([onSelect] reports the item
/// number), so the strip stays inert chrome while the canvas is in edit mode
/// (issue #378).
class PatchTabStrip extends StatelessWidget {
  const PatchTabStrip({
    required this.labels,
    required this.selected,
    required this.voice,
    this.onSelect,
    super.key,
  });

  /// Every item's name, in order.
  final List<String> labels;

  /// The selected item numbers.
  final Set<int> selected;

  /// Voice index in `[1, 6]`; a lit tab takes its colour.
  final int voice;

  /// Called with the number of the tab that was tapped.
  final ValueChanged<int>? onSelect;

  /// Key on item [index]'s tab, so a test can tap one of many.
  static Key itemKey(int index) => Key('PatchTabStrip.item.$index');

  /// Thickness of a lit tab's underline.
  static const double underline = 2;

  @override
  Widget build(BuildContext context) {
    final color = PhiVoices.color(voice);
    final glow = PhiVoices.glow(voice);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        border: Border.all(color: PhiColors.line2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                key: itemKey(i),
                behavior: HitTestBehavior.opaque,
                onTap: onSelect == null ? null : () => onSelect!(i),
                child: _tab(labels[i], selected.contains(i), i, color, glow),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tab(String label, bool on, int index, Color color, Color glow) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: on ? glow : null,
        border: Border(
          left: index == 0
              ? BorderSide.none
              : const BorderSide(color: PhiColors.line2),
          bottom: BorderSide(
            color: on ? color : color.withAlpha(0),
            width: underline,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PatchCanvasConstants.objectBoxPaddingH,
        ),
        child: Center(
          child: Text(
            label,
            style: PhiType.monoS().copyWith(
              color: on ? PhiColors.fg0 : PhiColors.fg2,
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
