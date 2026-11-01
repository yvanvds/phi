import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/function_point.dart';

void main() {
  test('parses a <x> <y> <curve> cell', () {
    expect(
      FunctionPoint.parse('100 0.5 -0.25'),
      const FunctionPoint(100, 0.5, -0.25),
    );
    expect(FunctionPoint.parse('100 0.5'), const FunctionPoint(100, 0.5));
    expect(FunctionPoint.parse(''), isNull);
    expect(FunctionPoint.parse('clear'), isNull);
  });

  test('shapes a segment as the engine does', () {
    expect(FunctionPoint.shape(0.5, 0), 0.5);
    expect(FunctionPoint.shape(0.5, 0.5), closeTo(0.125, 1e-9));
    expect(FunctionPoint.shape(0.125, -0.5), closeTo(0.5, 1e-9));
    expect(FunctionPoint.shape(0.99, 1), 0, reason: 'held to the end');
    expect(FunctionPoint.shape(1, 1), 1);
    expect(FunctionPoint.shape(0.01, -1), 1, reason: 'jumps at the start');
    expect(FunctionPoint.shape(0, -1), 0);
  });
}
