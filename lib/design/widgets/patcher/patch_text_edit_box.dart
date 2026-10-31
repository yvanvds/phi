import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import 'patch_canvas_constants.dart';

/// The `.textedit` object drawn as **only itself**: a plain rectangular field
/// with a text underline, the shape that says "type here" (issue #470).
///
/// Square-cornered like a number box but with neither its cut corner nor a
/// message box's notch — what tells it from both is the rule along its foot,
/// which brightens to the voice colour while the field holds the keyboard.
///
/// Visual-only: the field itself, its focus and its keys are the caller's
/// ([child]).
class PatchTextEditBox extends StatelessWidget {
  const PatchTextEditBox({
    required this.child,
    this.focused = false,
    this.accent = PhiColors.fg2,
    super.key,
  });

  /// The text field, laid out inside the box.
  final Widget child;

  /// Whether the field holds the keyboard — the underline takes [accent].
  final bool focused;

  /// The underline's colour while [focused].
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        border: Border(
          top: const BorderSide(color: PhiColors.line2),
          left: const BorderSide(color: PhiColors.line2),
          right: const BorderSide(color: PhiColors.line2),
          bottom: BorderSide(color: focused ? accent : PhiColors.fg3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PatchCanvasConstants.objectBoxPaddingH,
          vertical: PatchCanvasConstants.objectBoxPaddingV,
        ),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }
}
