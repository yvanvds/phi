import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';

/// The title-bar dirty indicator (design `docs/design/project-registry.md` §9):
/// a small dot that appears while the open project has unsaved changes and
/// vanishes once it is saved.
///
/// Binds to a `ProjectController.isDirty` [ValueListenable] so it repaints on
/// exactly that signal, independent of the rest of the toolbar.
class DirtyIndicator extends StatelessWidget {
  const DirtyIndicator({required this.isDirty, super.key});

  /// Whether the open project has unsaved changes.
  final ValueListenable<bool> isDirty;

  static const Widget _dot = Tooltip(
    message: 'unsaved changes',
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: PhiColors.warm,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: PhiColors.warm, blurRadius: 6)],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDirty,
      builder: (context, dirty, _) =>
          SizedBox(width: 8, height: 8, child: dirty ? _dot : null),
    );
  }
}
