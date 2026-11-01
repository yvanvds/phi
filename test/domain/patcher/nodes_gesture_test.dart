import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/field_node.dart';
import 'package:phi/domain/patcher/nodes_edit.dart';
import 'package:phi/domain/patcher/nodes_gesture.dart';
import 'package:phi/domain/patcher/nodes_view.dart';

void main() {
  // A 100-pixel field inset 6: step 0.01.
  final view = NodesView(width: 112, height: 112);
  const nodes = [FieldNode(0.25, 0.25, 0.2), FieldNode(0.75, 0.75, 0.1)];
  (double, double) at(double x, double y) => view.toPixel(x, y);

  NodesGesture gesture() => NodesGesture(view: view, nodes: nodes);

  test('a press puts the cursor there and a drag carries it', () {
    final g = gesture();
    final (px, py) = at(0.5, 0.5);
    expect(g.down(px, py), const NodesEdit.cursor(0.5, 0.5));
    final (qx, qy) = at(0.25, 0.75);
    expect(g.moveTo(qx, qy), const NodesEdit.cursor(0.25, 0.75));
    expect(g.moveTo(qx + 0.2, qy), isNull, reason: 'the same snapped point');
    expect(g.selected, isNull);
  });

  test('the cursor stays inside the field', () {
    final g = gesture()..down(56, 56);
    expect(g.moveTo(-40, 300), const NodesEdit.cursor(0, 0));
  });

  test('an alt-drag on a node moves it by where it was grabbed', () {
    final g = gesture();
    final (px, py) = at(0.3, 0.25);
    expect(g.down(px, py, alt: true), isNull, reason: 'a grab sends nothing');
    expect(g.selected, 0);
    final (qx, qy) = at(0.55, 0.45);
    expect(g.moveTo(qx, qy), const NodesEdit.move(0, 0.5, 0.45));
    expect(g.moveTo(qx, qy), isNull);
  });

  test('a moved centre stays inside the field', () {
    final g = gesture();
    final (px, py) = at(0.75, 0.75);
    g.down(px, py, alt: true);
    expect(g.moveTo(px + 200, py - 200), const NodesEdit.move(1, 1, 1));
  });

  test('an alt-drag on a rim sets the radius to the pointer distance', () {
    final g = gesture();
    final (px, py) = at(0.85, 0.75);
    g.down(px, py, alt: true);
    expect(g.selected, 1);
    final (qx, qy) = at(0.75, 0.45);
    expect(g.moveTo(qx, qy), const NodesEdit.resize(1, 0.75, 0.75, 0.3));
  });

  test('a radius is kept between the minimum and the field diagonal', () {
    final g = gesture();
    final (px, py) = at(0.85, 0.75);
    g.down(px, py, alt: true);
    final (cx, cy) = at(0.75, 0.75);
    expect(
      g.moveTo(cx, cy),
      const NodesEdit.resize(1, 0.75, 0.75, NodesView.minRadius),
    );
    expect(g.moveTo(cx - 900, cy + 900)!.radius, 1.41);
  });

  test('an alt-press on empty space does nothing', () {
    final g = gesture();
    final (px, py) = at(0.5, 0.95);
    expect(g.down(px, py, alt: true), isNull);
    expect(g.moveTo(px - 30, py), isNull);
    expect(g.selected, isNull);
  });

  test('a lifted pointer ends the gesture', () {
    final g = gesture()..down(56, 56);
    g.up();
    expect(g.moveTo(20, 20), isNull);
  });
}
