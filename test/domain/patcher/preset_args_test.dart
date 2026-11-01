import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/preset_args.dart';

void main() {
  test('no argument is the engine default of 32 slots', () {
    expect(PresetArgs.parse('').slots, 32);
    expect(PresetArgs.parse('  ').slots, 32);
  });

  test('the first number is the capacity, truncated and clamped to 1-1024', () {
    expect(PresetArgs.parse('8').slots, 8);
    expect(PresetArgs.parse('4.9').slots, 4);
    expect(PresetArgs.parse('0').slots, 1);
    expect(PresetArgs.parse('-5').slots, 1);
    expect(PresetArgs.parse('5000').slots, 1024);
    expect(PresetArgs.parse('bank 12').slots, 12, reason: 'words are skipped');
  });
}
