import 'dart:math' as math;

import 'field_node.dart';
import 'function_view.dart';
import 'nodes_hit.dart';
import 'nodes_hit_part.dart';

/// How a `.nodes` field maps onto the pixels of its box (issue #476).
///
/// The field is the unit square, x to the right and y **up** (as on the
/// `.xyslider`), drawn as the largest square that fits the box less [inset] on
/// every side, centred in it. Pixel positions are in the box's own
/// coordinates, origin top left. The engine bounds nothing, so a node may sit
/// or reach outside the square; the editor keeps what it places inside it.
///
/// Values read off a pixel snap to [step], a power of ten no finer than one
/// pixel's worth, so a drag lands on a number a person would type.
class NodesView {
  /// The field fitted into a [width] by [height] box.
  factory NodesView({required double width, required double height}) {
    final side = math.max(0.0, math.min(width, height) - 2 * inset);
    return NodesView._(side, (width - side) / 2, (height - side) / 2);
  }

  const NodesView._(this.side, this.left, this.top);

  /// The gap between the box's edge and the field, in pixels.
  static const double inset = 6;

  /// How close to a node's edge, in pixels, a press takes the rim.
  static const double rimTolerance = 5;

  /// A press this close to a node's centre, in pixels, always takes its body —
  /// so even a tiny node can be grabbed and moved.
  static const double handle = 4;

  /// The smallest radius a rim drag leaves, in field units.
  static const double minRadius = 0.01;

  /// The largest radius a rim drag gives: the field's diagonal, past which a
  /// node covers the whole square from anywhere inside it.
  static const double maxRadius = math.sqrt2;

  /// The field's side, in pixels.
  final double side;

  /// The field's left edge, in pixels.
  final double left;

  /// The field's top edge, in pixels.
  final double top;

  /// The value step one pixel is worth, rounded down to a power of ten.
  double get step {
    if (!(side > 0)) return 0;
    final exponent = (math.log(1 / side) / math.ln10).floor();
    return math.pow(10, exponent).toDouble();
  }

  /// [value] snapped to [step].
  double snap(double value) => FunctionView.snap(value, step);

  /// The pixel position of field point ([x], [y]).
  (double, double) toPixel(double x, double y) =>
      (left + x * side, top + (1 - y) * side);

  /// [length] field units in pixels.
  double toPixels(double length) => length * side;

  /// The field point under pixel ([px], [py]), neither snapped nor clamped.
  (double, double) fieldAt(double px, double py) {
    if (!(side > 0)) return (0, 0);
    return ((px - left) / side, 1 - (py - top) / side);
  }

  /// The field point under pixel ([px], [py]), snapped and kept inside the
  /// square.
  (double, double) clampedAt(double px, double py) {
    final (x, y) = fieldAt(px, py);
    return (snap(x.clamp(0.0, 1.0)), snap(y.clamp(0.0, 1.0)));
  }

  /// What a press at ([px], [py]) lands on, or null for none.
  ///
  /// A rim within [rimTolerance] wins, the nearest edge first — unless the
  /// press is within [handle] of that node's centre. Otherwise the node whose
  /// circle holds the press (or whose centre is within [handle]), the nearest
  /// centre first. Ties go to the higher index, the node drawn on top.
  NodesHit? hit(List<FieldNode> nodes, double px, double py) {
    int? rim;
    var rimBest = double.infinity;
    int? body;
    var bodyBest = double.infinity;
    for (var i = 0; i < nodes.length; i++) {
      final (cx, cy) = toPixel(nodes[i].x, nodes[i].y);
      final d = math.sqrt(math.pow(px - cx, 2) + math.pow(py - cy, 2));
      final r = nodes[i].radius > 0 ? toPixels(nodes[i].radius) : 0.0;
      final edge = (d - r).abs();
      if (r > 0 && edge <= rimTolerance && d > handle && edge <= rimBest) {
        rim = i;
        rimBest = edge;
      }
      if ((d < r || d <= handle) && d <= bodyBest) {
        body = i;
        bodyBest = d;
      }
    }
    if (rim != null) return NodesHit(rim, NodesHitPart.rim);
    if (body != null) return NodesHit(body, NodesHitPart.body);
    return null;
  }
}
