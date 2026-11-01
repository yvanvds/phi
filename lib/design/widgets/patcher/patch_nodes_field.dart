import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../domain/patcher/field_node.dart';
import '../../../domain/patcher/nodes_view.dart';
import '../../tokens/phi_colors.dart';
import '../../tokens/phi_radii.dart';
import '../../tokens/phi_type.dart';
import '../../tokens/phi_voices.dart';

/// The `.nodes` object drawn as **only itself**: a square field of numbered,
/// translucent circles in the voice colour, each filled by the weight the
/// cursor gives it, and the cursor (issue #476).
///
/// Nodes and cursor are in field units — the unit square, y up — and placed by
/// [NodesView], so the widget and the gestures over it agree to the pixel. A
/// node is numbered from 1, as Max numbers them; the [selected] one is drawn
/// with a bolder rim.
///
/// Visual-only: moving the cursor and laying the nodes out belong to the
/// caller, so the field stays inert chrome while the canvas is in edit mode
/// (issue #378).
class PatchNodesField extends StatelessWidget {
  const PatchNodesField({
    required this.nodes,
    required this.weights,
    required this.cursor,
    required this.voice,
    this.selected,
    super.key,
  });

  /// Every node, in node order.
  final List<FieldNode> nodes;

  /// Each node's weight in [0, 1], in node order; a missing one reads as 0.
  final List<double> weights;

  /// The cursor's position in the field.
  final (double, double) cursor;

  /// Voice index in `[1, 6]`; the nodes take its colour.
  final int voice;

  /// The node a layout drag holds, if any.
  final int? selected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        border: Border.all(color: PhiColors.line1),
        borderRadius: PhiRadii.all2,
      ),
      child: ClipRect(
        child: CustomPaint(
          size: Size.infinite,
          painter: _FieldPainter(
            nodes: nodes,
            weights: weights,
            cursor: cursor,
            selected: selected,
            color: PhiVoices.color(voice),
            label: PhiType.monoS(),
          ),
        ),
      ),
    );
  }
}

class _FieldPainter extends CustomPainter {
  const _FieldPainter({
    required this.nodes,
    required this.weights,
    required this.cursor,
    required this.selected,
    required this.color,
    required this.label,
  });

  final List<FieldNode> nodes;
  final List<double> weights;
  final (double, double) cursor;
  final int? selected;
  final Color color;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    final view = NodesView(width: size.width, height: size.height);
    if (!(view.side > 0)) return;
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.side, view.side),
      Paint()
        ..color = PhiColors.line1
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final (cx, cy) = view.toPixel(node.x, node.y);
      final centre = Offset(cx, cy);
      final weight = i < weights.length ? weights[i].clamp(0.0, 1.0) : 0.0;
      if (node.radius > 0) {
        final r = view.toPixels(node.radius);
        canvas
          ..drawCircle(
            centre,
            r,
            Paint()..color = color.withValues(alpha: 0.08 + 0.5 * weight),
          )
          ..drawCircle(
            centre,
            r,
            Paint()
              ..color = color.withValues(alpha: i == selected ? 1 : 0.6)
              ..style = PaintingStyle.stroke
              ..strokeWidth = i == selected ? 2 : 1,
          );
      }
      canvas.drawCircle(centre, 2, Paint()..color = color);
      final text = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: label.copyWith(color: PhiColors.fg1),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, centre + const Offset(3, -2) - Offset(0, text.height));
    }

    final (x, y) = cursor;
    final (px, py) = view.toPixel(x, y);
    final at = Offset(px, py);
    canvas
      ..drawCircle(at, 4, Paint()..color = PhiColors.fg0)
      ..drawCircle(
        at,
        6.5,
        Paint()
          ..color = PhiColors.fg0
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
  }

  @override
  bool shouldRepaint(_FieldPainter oldDelegate) =>
      oldDelegate.selected != selected ||
      oldDelegate.color != color ||
      oldDelegate.cursor != cursor ||
      oldDelegate.label != label ||
      !listEquals(oldDelegate.nodes, nodes) ||
      !listEquals(oldDelegate.weights, weights);
}
