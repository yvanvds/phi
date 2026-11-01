import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/multislider_args.dart';

void main() {
  test('empty args are the engine defaults: 8 cells over 0-127', () {
    final args = MultisliderArgs.parse('');
    expect(args.size, 8);
    expect(args.range.low, 0);
    expect(args.range.high, 127);
  });

  test('reads size, minimum and maximum', () {
    final args = MultisliderArgs.parse('16 -1 1');
    expect(args.size, 16);
    expect(args.range.low, -1);
    expect(args.range.high, 1);
  });

  test('clamps the size to 1-1024', () {
    expect(MultisliderArgs.parse('0').size, 1);
    expect(MultisliderArgs.parse('5000').size, 1024);
    expect(MultisliderArgs.parse('4.7').size, 4);
    expect(MultisliderArgs.parse('lots').size, 8);
  });
}
