import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/shell_layout/layout_node.dart';

/// Renders one [LayoutPane] leaf — its tab stack (design
/// `docs/design/shell-layout.md` §2). The active tab paints; the rest stay
/// resident but offstage so their state (scroll, selection, in-progress edits)
/// survives switching without a tab strip, exactly as the pre-refactor
/// `IndexedStack` did for the single centre surface.
///
/// Content is built through [contentFor], which the shell supplies so it can
/// key each surface (single-instance identity, so a cross-pane move re-parents
/// rather than rebuilds) and special-case the Scene GL viewport (mounted only
/// while it is the visible tab). An empty pane — only ever the sole surviving
/// pane — shows a quiet placeholder.
class SurfacePane extends StatelessWidget {
  const SurfacePane({required this.pane, required this.contentFor, super.key});

  final LayoutPane pane;

  /// Builds the resident content for [surfaceId]; [active] is whether it is this
  /// pane's foreground tab (the shell gates the Scene viewport on it).
  final Widget Function(String surfaceId, {required bool active}) contentFor;

  @override
  Widget build(BuildContext context) {
    if (pane.tabs.isEmpty) return const _EmptyPane();
    final activeIndex = pane.active == null
        ? 0
        : pane.tabs.indexOf(pane.active!).clamp(0, pane.tabs.length - 1);
    return IndexedStack(
      index: activeIndex,
      sizing: StackFit.expand,
      children: [
        for (var i = 0; i < pane.tabs.length; i++)
          contentFor(pane.tabs[i], active: i == activeIndex),
      ],
    );
  }
}

/// Placeholder shown in the last pane when it has been emptied — the tree keeps
/// one pane alive by construction, so this stands in until a surface is summoned
/// back into it.
class _EmptyPane extends StatelessWidget {
  const _EmptyPane();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: PhiColors.bg0,
    child: Center(
      child: Text(
        'no surface open',
        style: PhiType.mono().copyWith(color: PhiColors.fg2, fontSize: 12),
      ),
    ),
  );
}
