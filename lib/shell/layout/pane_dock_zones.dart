import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../domain/shell_layout/drop_edge.dart';
import 'tab_drag_data.dart';

/// The drop-zone overlay for a pane body (design `docs/design/shell-layout.md`
/// §2 — "drag a tab to a pane edge to split (half → quadrant), to a pane centre
/// to join its stack"). It lays five [DragTarget]s over the surface content:
/// four edge bands ([DropEdge.left]/[right]/[top]/[bottom]) that **split** the
/// pane, and a centre region that **joins** the dragged surface into the stack.
///
/// The zones are transparent and translucent when idle — a plain tap falls
/// through to the surface below — and light up only while a compatible tab is
/// hovering (`candidateData` non-empty), so the docking affordance appears
/// exactly during a drag. An out-of-band release is simply not accepted, so the
/// drag snaps back. The layout ops themselves live in [ShellLayout]; this widget
/// only names the zone and forwards the dragged [TabDragData].
class PaneDockZones extends StatelessWidget {
  const PaneDockZones({
    required this.paneId,
    required this.onSplit,
    required this.onJoin,
    super.key,
  });

  /// The pane these zones dock into — used only to key the zones for tests.
  final String paneId;

  /// Splits this pane on [edge], placing the dragged surface beside/above it.
  final void Function(TabDragData data, DropEdge edge) onSplit;

  /// Joins the dragged surface into this pane's tab stack.
  final ValueChanged<TabDragData> onJoin;

  /// The fraction of each side taken by its edge band; the centre is what's left.
  static const double _edgeBand = 0.25;

  /// Test handle for an edge (split) zone.
  static Key edgeZoneKey(String paneId, DropEdge edge) =>
      ValueKey('dock-$paneId-${edge.name}');

  /// Test handle for the centre (join) zone.
  static Key centerZoneKey(String paneId) => ValueKey('dock-$paneId-center');

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bandW = constraints.maxWidth * _edgeBand;
        final bandH = constraints.maxHeight * _edgeBand;
        return Stack(
          children: [
            // Left / right bands own the full height (including the corners).
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: bandW,
              child: _EdgeZone(
                key: edgeZoneKey(paneId, DropEdge.left),
                edge: DropEdge.left,
                onSplit: onSplit,
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: bandW,
              child: _EdgeZone(
                key: edgeZoneKey(paneId, DropEdge.right),
                edge: DropEdge.right,
                onSplit: onSplit,
              ),
            ),
            // Top / bottom bands span the middle column between the side bands.
            Positioned(
              left: bandW,
              right: bandW,
              top: 0,
              height: bandH,
              child: _EdgeZone(
                key: edgeZoneKey(paneId, DropEdge.top),
                edge: DropEdge.top,
                onSplit: onSplit,
              ),
            ),
            Positioned(
              left: bandW,
              right: bandW,
              bottom: 0,
              height: bandH,
              child: _EdgeZone(
                key: edgeZoneKey(paneId, DropEdge.bottom),
                edge: DropEdge.bottom,
                onSplit: onSplit,
              ),
            ),
            // Centre = the middle rectangle → join.
            Positioned(
              left: bandW,
              right: bandW,
              top: bandH,
              bottom: bandH,
              child: DragTarget<TabDragData>(
                key: centerZoneKey(paneId),
                onAcceptWithDetails: (details) => onJoin(details.data),
                builder: (context, candidate, rejected) =>
                    _Highlight(active: candidate.isNotEmpty),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One edge (split) zone.
class _EdgeZone extends StatelessWidget {
  const _EdgeZone({required this.edge, required this.onSplit, super.key});

  final DropEdge edge;
  final void Function(TabDragData data, DropEdge edge) onSplit;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TabDragData>(
      onAcceptWithDetails: (details) => onSplit(details.data, edge),
      builder: (context, candidate, rejected) =>
          _Highlight(active: candidate.isNotEmpty),
    );
  }
}

/// A zone's fill: transparent when idle (taps pass through), a soft accent wash
/// with a hot border while a tab hovers.
class _Highlight extends StatelessWidget {
  const _Highlight({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    if (!active) return const SizedBox.expand();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PhiColors.voice1Soft,
        border: Border.all(color: PhiColors.lineHot),
      ),
      child: const SizedBox.expand(),
    );
  }
}
