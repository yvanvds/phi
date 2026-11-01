import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/function_args.dart';

void main() {
  test('defaults to 128 points over 0-1', () {
    final args = FunctionArgs.parse('');
    expect(args.capacity, 128);
    expect(args.range.low, 0);
    expect(args.range.high, 1);
  });

  test('reads the capacity, clamped, then an ordered y range', () {
    final args = FunctionArgs.parse('16 10 -2');
    expect(args.capacity, 16);
    expect(args.range.low, -2);
    expect(args.range.high, 10);
    expect(FunctionArgs.parse('1').capacity, 2);
    expect(FunctionArgs.parse('5000').capacity, 1024);
    expect(FunctionArgs.parse('7.9').capacity, 7, reason: 'truncated');
  });

  test('skips tokens that are not numbers', () {
    final args = FunctionArgs.parse('points 8 lo 0 127');
    expect(args.capacity, 8);
    expect(args.range.high, 127);
  });
}
