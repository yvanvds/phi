import 'package:flutter/widgets.dart';

import '../../../domain/patcher/patch_cable.dart';
import '../../../domain/patcher/patch_port_id.dart';
import '../../../domain/patcher/patch_port_kind.dart';
import '../../tokens/phi_colors.dart';
import '../../tokens/phi_voices.dart';
import 'patch_canvas_constants.dart';

/// Painter for one or more cables on the patcher canvas.
///
/// Walks the supplied cables, looks each endpoint up in [portPositions],
/// and draws a cubic bezier between them — voice-coloured, with a
/// blurred glow underneath, dashed when control-rate.
class PatchCablePainter extends CustomPainter {
  PatchCablePainter({
    required this.cables,
    required this.portPositions,
    required this.cableVoiceForSource,
    required this.version,
    this.selected,
  });

  /// Cables to draw, in order (last wins on overlap).
  final List<PatchCable> cables;

  /// Canvas-local centre position of every port currently rendered. The
  /// painter silently skips any cable referencing a missing endpoint.
  final Map<PatchPortId, Offset> portPositions;

  /// Voice index (1..6) per source port — controls cable colour.
  final Map<PatchPortId, int> cableVoiceForSource;

  /// The currently-selected cable, drawn with a bright highlight, or null.
  final PatchCable? selected;

  /// Bumped whenever the graph changes — used by [shouldRepaint] as a
  /// cheap int comparison instead of deep-equals.
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    for (final cable in cables) {
      final a = portPositions[cable.source];
      final b = portPositions[cable.target];
      if (a == null || b == null) continue;
      final voice = cableVoiceForSource[cable.source] ?? 1;
      _drawCable(
        canvas,
        a,
        b,
        voice,
        cable.kind,
        isSelected: cable == selected,
      );
    }
  }

  static void _drawCable(
    Canvas canvas,
    Offset a,
    Offset b,
    int voice,
    PatchPortKind kind, {
    required bool isSelected,
  }) {
    final color = PhiVoices.color(voice);
    final glow = PhiVoices.glow(voice);
    const cx = PatchCanvasConstants.cableControlOffset;

    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..cubicTo(a.dx + cx, a.dy, b.dx - cx, b.dy, b.dx, b.dy);

    // A selected cable wears a wide bright halo under the wire so it reads as
    // picked regardless of its voice colour.
    if (isSelected) {
      canvas.drawPath(
        path,
        Paint()
          ..color = PhiColors.fg0
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }

    final glowPaint = Paint()
      ..color = glow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final corePaint = Paint()
      ..color = isSelected ? PhiColors.fg0 : color
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 2 : 1.2;

    canvas.drawPath(path, glowPaint);

    if (kind == PatchPortKind.control) {
      canvas.drawPath(_dashed(path, dash: 4, gap: 3), corePaint);
    } else {
      canvas.drawPath(path, corePaint);
    }
  }

  static Path _dashed(
    Path source, {
    required double dash,
    required double gap,
  }) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      while (distance < metric.length) {
        final next = distance + (draw ? dash : gap);
        if (draw) {
          out.addPath(
            metric.extractPath(distance, next.clamp(0.0, metric.length)),
            Offset.zero,
          );
        }
        distance = next;
        draw = !draw;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant PatchCablePainter old) =>
      old.version != version || old.selected != selected;
}
