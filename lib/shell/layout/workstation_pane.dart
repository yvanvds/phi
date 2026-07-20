import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../domain/shell_layout/layout_node.dart';
import 'pane_dock_zones.dart';
import 'pane_tab_strip.dart';
import 'shell_layout_controller.dart';
import 'surface_pane.dart';

/// One pane, fully dressed: a [PaneTabStrip] above its resident [SurfacePane],
/// with the [PaneDockZones] drop overlay and — when this is the focused pane — a
/// visible focus ring (design `docs/design/shell-layout.md` §2). This is the
/// widget the split tree hands each leaf to; it turns the interaction callbacks
/// into [ShellLayoutController] mutations so every structural rule stays in the
/// pure domain.
///
/// Focus follows interaction: a pointer-down anywhere in the pane makes it the
/// active pane and takes keyboard focus, so Ctrl+Tab (handled up in the shell)
/// cycles *this* pane's tabs. The seed pane autofocuses at boot so the shortcut
/// works before any click. The ring makes the focused pane legible at a glance.
class WorkstationPane extends StatefulWidget {
  const WorkstationPane({
    required this.pane,
    required this.isActivePane,
    required this.controller,
    required this.contentFor,
    required this.labelFor,
    super.key,
  });

  /// The pane to render.
  final LayoutPane pane;

  /// Whether this pane is the focused one (accented strip + focus ring).
  final bool isActivePane;

  /// The layout owner the interactions drive.
  final ShellLayoutController controller;

  /// Builds a surface's resident content; `active` gates the Scene viewport.
  final Widget Function(String surfaceId, {required bool active}) contentFor;

  /// Maps a surface id to its tab label.
  final String Function(String surfaceId) labelFor;

  /// Test handle for the focused-pane ring (present only while active).
  static Key focusRingKey(String paneId) => ValueKey('pane-focus-$paneId');

  @override
  State<WorkstationPane> createState() => _WorkstationPaneState();
}

class _WorkstationPaneState extends State<WorkstationPane> {
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'pane-${widget.pane.id}',
    skipTraversal: true,
  );

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _takeFocus() {
    widget.controller.setActivePane(widget.pane.id);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final paneId = widget.pane.id;
    return Focus(
      focusNode: _focusNode,
      // The seed/active pane grabs focus at boot so Ctrl+Tab works pre-click.
      autofocus: widget.isActivePane,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _takeFocus(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PaneTabStrip(
              pane: widget.pane,
              isActivePane: widget.isActivePane,
              labelFor: widget.labelFor,
              onSelect: controller.activate,
              onClose: controller.close,
              onReorder: (from, to) => controller.reorderTab(paneId, from, to),
              onJoinAt: (data, at) =>
                  controller.moveSurface(data.surfaceId, paneId, atIndex: at),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SurfacePane(
                      pane: widget.pane,
                      contentFor: widget.contentFor,
                    ),
                  ),
                  Positioned.fill(
                    child: PaneDockZones(
                      paneId: paneId,
                      onSplit: (data, edge) =>
                          controller.split(paneId, data.surfaceId, edge),
                      onJoin: (data) =>
                          controller.moveSurface(data.surfaceId, paneId),
                    ),
                  ),
                  if (widget.isActivePane)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          key: WorkstationPane.focusRingKey(paneId),
                          decoration: BoxDecoration(
                            border: Border.all(color: PhiColors.lineHot),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
