import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_radii.dart';
import '../../tokens/phi_type.dart';
import '../../tokens/phi_voices.dart';
import 'transform_graph_canvas_constants.dart';

/// Visual chrome for one transform-graph node: a rounded box carrying the
/// transform's kind tag, its label, and an active pill — the node-and-cable
/// counterpart of the linear chain's `TransformChip`.
///
/// Visual-only and domain-free (takes primitives, mirroring `StateNodeFrame`):
/// callers wrap it in a `GestureDetector` / `Listener` for drag, toggle, and
/// cable authoring. [open] dims the node when it is *not* part of the active
/// subgraph for the current context, so the canvas reads as a live view.
class TransformNodeFrame extends StatelessWidget {
  const TransformNodeFrame({
    required this.tag,
    required this.voiceIndex,
    required this.label,
    required this.active,
    this.open = true,
    super.key,
  });

  /// The transform kind's short tag (e.g. `pitch`, `struct`) — rendered upper.
  final String tag;

  /// Voice index in `[1, 6]` driving the tag / pill colour.
  final int voiceIndex;

  /// The transform's label (e.g. `transpose · +3 st`).
  final String label;

  /// Whether the wrapped transform is active. Inactive nodes pass their input
  /// through; the pill sits left and the label dims.
  final bool active;

  /// Whether this node is reachable in the active subgraph. Closed nodes fade.
  final bool open;

  @override
  Widget build(BuildContext context) {
    final color = PhiVoices.color(voiceIndex);
    final glow = PhiVoices.glow(voiceIndex);
    return Opacity(
      opacity: open ? 1 : 0.4,
      child: Container(
        width: TransformGraphCanvasConstants.nodeWidth,
        height: TransformGraphCanvasConstants.nodeHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: PhiColors.bg1,
          border: Border.all(
            color: active ? color.withValues(alpha: 0.5) : PhiColors.line1,
          ),
          borderRadius: PhiRadii.all2,
          boxShadow: active ? [BoxShadow(color: glow, blurRadius: 12)] : null,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(
                tag.toUpperCase(),
                style: PhiType.monoS().copyWith(
                  fontSize: 8,
                  color: active ? color : PhiColors.fg3,
                  letterSpacing: 0.08 * 8,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: PhiType.monoS().copyWith(
                  fontSize: 11,
                  color: active ? PhiColors.fg0 : PhiColors.fg3,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 6),
            _Pill(active: active, color: color, glow: glow),
          ],
        ),
      ),
    );
  }
}

/// The 20×10 active pill, matching the chain chip's toggle.
class _Pill extends StatelessWidget {
  const _Pill({required this.active, required this.color, required this.glow});

  final bool active;
  final Color color;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 10,
      decoration: BoxDecoration(
        color: active ? color : PhiColors.fg4,
        borderRadius: PhiRadii.allPill,
        boxShadow: active ? [BoxShadow(color: glow, blurRadius: 6)] : null,
      ),
      child: AnimatedAlign(
        alignment: active ? Alignment.centerRight : Alignment.centerLeft,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 1),
          child: SizedBox(
            width: 8,
            height: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: PhiColors.bg0,
                borderRadius: PhiRadii.allPill,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
