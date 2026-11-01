import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/field_node.dart';
import 'package:phi/domain/patcher/nodes_hit.dart';
import 'package:phi/domain/patcher/nodes_hit_part.dart';
import 'package:phi/domain/patcher/nodes_view.dart';

void main() {
  // A 112-pixel box: a 100-pixel field inset 6 on each side.
  final view = NodesView(width: 112, height: 112);

  test('the field is the largest inset square, centred in the box', () {
    expect(view.side, 100);
    expect((view.left, view.top), (6.0, 6.0));
    final wide = NodesView(width: 212, height: 112);
    expect(wide.side, 100);
    expect((wide.left, wide.top), (56.0, 6.0));
  });

  test('field points map to pixels with y up, and back', () {
    expect(view.toPixel(0, 0), (6.0, 106.0));
    expect(view.toPixel(1, 1), (106.0, 6.0));
    expect(view.fieldAt(56, 31), (0.5, 0.75));
    expect(view.toPixels(0.25), 25);
  });

  test('a pixel snaps to a power-of-ten step, clamped into the field', () {
    expect(view.step, 0.01);
    expect(view.clampedAt(56.4, 31), (0.5, 0.75));
    expect(view.clampedAt(-20, 200), (0.0, 0.0));
    expect(NodesView(width: 172, height: 172).step, 0.001);
  });

  group('hit', () {
    const nodes = [FieldNode(0.25, 0.25, 0.2), FieldNode(0.75, 0.75, 0.1)];

    test('inside a circle takes its body', () {
      final (px, py) = view.toPixel(0.3, 0.25);
      expect(view.hit(nodes, px, py), const NodesHit(0, NodesHitPart.body));
    });

    test('near the edge takes the rim, inside or out', () {
      var (px, py) = view.toPixel(0.75 + 0.1, 0.75);
      expect(view.hit(nodes, px - 3, py), const NodesHit(1, NodesHitPart.rim));
      expect(view.hit(nodes, px + 4, py), const NodesHit(1, NodesHitPart.rim));
      (px, py) = view.toPixel(0.25, 0.25 - 0.2);
      expect(view.hit(nodes, px, py), const NodesHit(0, NodesHitPart.rim));
    });

    test('empty space takes nothing', () {
      final (px, py) = view.toPixel(0.5, 0.95);
      expect(view.hit(nodes, px, py), isNull);
    });

    test('the centre of a tiny node takes its body, not its rim', () {
      const tiny = [FieldNode(0.5, 0.5, 0.02)];
      final (px, py) = view.toPixel(0.5, 0.5);
      expect(view.hit(tiny, px, py), const NodesHit(0, NodesHitPart.body));
      expect(view.hit(tiny, px + 6, py), const NodesHit(0, NodesHitPart.rim));
    });

    test('overlapping nodes go to the nearest centre, then the top one', () {
      final start = List.filled(4, const FieldNode(0, 0, 1));
      final (px, py) = view.toPixel(0.2, 0.2);
      expect(view.hit(start, px, py), const NodesHit(3, NodesHitPart.body));
      const nested = [FieldNode(0.5, 0.5, 0.4), FieldNode(0.6, 0.5, 0.05)];
      final (qx, qy) = view.toPixel(0.6, 0.5);
      expect(view.hit(nested, qx, qy), const NodesHit(1, NodesHitPart.body));
    });
  });
}
