import 'package:flutter/widgets.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../design/widgets/midi_graph/transform_graph_canvas_constants.dart';
import '../../../design/widgets/midi_graph/transform_node_frame.dart';
import '../../../domain/midi/graph/transform_node.dart';
import '../../../domain/midi/graph/transform_node_id.dart';
import '../../../engine/state/midi_graph_controller.dart';

/// Binds one graph vertex to its visual frame and routes gestures.
///
/// Handles both a real [node] (a `TransformNodeFrame` with a tap-to-toggle and
/// right-click-to-remove) and — when [node] is `null` — the clip-source
/// sentinel (a distinct `SOURCE` box). Every node carries an output port on
/// its right edge: pressing it starts a drag-to-connect via [onPortDown].
///
/// A body pan moves the node, *unless* a cable drag is already in flight
/// (`controller.dragSourceId != null`) — so dragging a cable never also drags
/// the node underneath.
class TransformGraphNodeView extends StatelessWidget {
  const TransformGraphNodeView({
    required this.id,
    required this.controller,
    required this.onPortDown,
    this.node,
    this.sourceNoteCount = 0,
    this.open = true,
    this.onToggle,
    this.onRemove,
    super.key,
  });

  final TransformNodeId id;
  final MidiGraphController controller;

  /// The wrapped vertex, or `null` for the source sentinel.
  final TransformNode? node;

  /// Note count shown on the source box (ignored for real nodes).
  final int sourceNoteCount;

  /// Whether this node is in the active subgraph for the current context.
  final bool open;

  /// Called when the output port is pressed, to begin a cable drag.
  final void Function(TransformNodeId from, Offset globalPosition) onPortDown;

  /// Tap handler for a real node (toggles active). `null` for the source.
  final VoidCallback? onToggle;

  /// Right-click handler for a real node (remove), given the global position.
  final void Function(Offset globalPosition)? onRemove;

  bool get _isSource => node == null;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) {
        if (controller.dragSourceId != null) return;
        controller.moveNode(id, d.delta);
      },
      onTap: _isSource ? null : onToggle,
      onSecondaryTapDown: _isSource || onRemove == null
          ? null
          : (d) => onRemove!(d.globalPosition),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_isSource)
            _SourceBox(noteCount: sourceNoteCount)
          else
            TransformNodeFrame(
              tag: node!.transform.kind.tag,
              voiceIndex: node!.transform.kind.voiceIndex,
              label: node!.transform.label,
              active: node!.transform.active,
              open: open,
            ),
          Positioned(
            right: -TransformGraphCanvasConstants.portHitRadius / 2,
            top:
                (TransformGraphCanvasConstants.nodeHeight -
                    TransformGraphCanvasConstants.portHitRadius) /
                2,
            width: TransformGraphCanvasConstants.portHitRadius,
            height: TransformGraphCanvasConstants.portHitRadius,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (e) => onPortDown(id, e.position),
              child: const Center(child: _Port()),
            ),
          ),
        ],
      ),
    );
  }
}

/// The visible output-port dot.
class _Port extends StatelessWidget {
  const _Port();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: TransformGraphCanvasConstants.portSize,
      height: TransformGraphCanvasConstants.portSize,
      decoration: BoxDecoration(
        color: PhiColors.bg3,
        shape: BoxShape.circle,
        border: Border.all(color: PhiColors.fg2),
      ),
    );
  }
}

/// The clip-source sentinel box.
class _SourceBox extends StatelessWidget {
  const _SourceBox({required this.noteCount});

  final int noteCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: TransformGraphCanvasConstants.sourceNodeWidth,
      height: TransformGraphCanvasConstants.nodeHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: PhiColors.bg2,
        border: Border.all(color: PhiColors.line2),
        borderRadius: PhiRadii.all2,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SOURCE',
            style: PhiType.caption().copyWith(
              color: PhiColors.fg2,
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$noteCount notes',
            style: PhiType.monoS().copyWith(color: PhiColors.fg1, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

/// Canvas-local rectangle of the node under [id] — used to build the
/// `Map<TransformNodeId, Rect>` the edge painter and hit-tester consume.
Rect graphNodeRect(MidiGraphController controller, TransformNodeId id) {
  final pos = controller.positionOf(id);
  final width = id.isSource
      ? TransformGraphCanvasConstants.sourceNodeWidth
      : TransformGraphCanvasConstants.nodeWidth;
  return Rect.fromLTWH(
    pos.dx,
    pos.dy,
    width,
    TransformGraphCanvasConstants.nodeHeight,
  );
}
