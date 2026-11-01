import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/nslider_args.dart';
import 'package:phi/domain/patcher/staff_drag.dart';

void main() {
  test('defaults to the whole MIDI range, spelled sharp', () {
    final args = NsliderArgs.parse('');
    expect(args.low, 0);
    expect(args.high, 127);
    expect(args.spelling, 1);
  });

  test('bounds sort and stay inside MIDI, as the engine bounds them', () {
    final args = NsliderArgs.parse('96 36 -1');
    expect(args.low, 36);
    expect(args.high, 96);
    expect(args.spelling, -1);
    expect(args.bound(10), 36);
    expect(args.bound(100), 96);
    expect(NsliderArgs.parse('-5 300').high, 127);
  });

  test('a staff drag moves a semitone per step of travel, up is higher', () {
    final drag = StaffDrag(start: 60, args: NsliderArgs.parse('48 72'));
    expect(drag.pitchAfter(0), 60);
    expect(drag.pitchAfter(-8), 62);
    expect(drag.pitchAfter(12), 57);
    expect(drag.pitchAfter(-400), 72, reason: 'held to the maximum');
    expect(drag.pitchAfter(400), 48);
  });
}
