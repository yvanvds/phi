import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/function_point.dart';
import 'package:phi/domain/patcher/function_view.dart';
import 'package:phi/domain/patcher/slider_range.dart';

void main() {
  FunctionView view(List<FunctionPoint> points, {double? domain}) =>
      FunctionView(
        points: points,
        range: SliderRange(0, 1),
        width: 200,
        height: 100,
        domain: domain,
      );

  test('the domain spans the points, or 1000 with none past 0', () {
    expect(view(const []).domain, 1000);
    expect(view(const [FunctionPoint(0, 1)]).domain, 1000);
    expect(view(const [FunctionPoint(0, 1), FunctionPoint(40, 0)]).domain, 40);
    expect(view(const [FunctionPoint(40, 0)], domain: 80).domain, 80);
  });

  test('maps values to pixels and back, snapped to a pixel step', () {
    final v = view(const []);
    expect(v.xStep, 1, reason: '1000 over 200 px is 5 a pixel');
    expect(v.yStep, 0.01);
    expect(v.xAt(100), 500);
    expect(v.xAt(101.4), 507);
    expect(v.xAt(-10), 0);
    expect(v.xAt(400), 2000, reason: 'not clamped on the right');
    expect(v.yAt(0), 1);
    expect(v.yAt(100), 0);
    expect(v.yAt(25), 0.75);
    expect(v.yAt(-30), 1, reason: 'clamped into the range');
    expect(v.xToPixel(250), 50);
    expect(v.yToPixel(0.25), 75);
  });

  test('finds the point and the segment under a pixel', () {
    final v = view(const [
      FunctionPoint(0, 0),
      FunctionPoint(500, 1),
      FunctionPoint(1000, 0),
    ]);
    expect(v.pointAt(102, 3), 1);
    expect(v.pointAt(120, 50), isNull);
    expect(v.segmentAt(50), 1);
    expect(v.segmentAt(150), 2);
    expect(view(const [FunctionPoint(0, 0)]).segmentAt(50), isNull);
  });

  test('snaps without float noise', () {
    expect(FunctionView.snap(0.1 + 0.2, 0.01), 0.3);
    expect(FunctionView.snap(12.345, 0.1), 12.3);
  });
}
