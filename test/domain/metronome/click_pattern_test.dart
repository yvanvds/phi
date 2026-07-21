import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/metronome/click_beat.dart';
import 'package:phi/domain/metronome/click_pattern.dart';

void main() {
  group('ClickPattern — one-bar click generation (#262)', () {
    test('generates one beat per meter numerator', () {
      for (final meter in [2, 3, 4, 5, 7]) {
        final beats = ClickPattern(beatsPerBar: meter).beats();
        expect(beats, hasLength(meter), reason: '$meter/bar has $meter clicks');
        expect(
          beats.map((b) => b.beat).toList(),
          [for (var i = 0; i < meter; i++) i],
          reason: 'beats are zero-based and in order',
        );
      }
    });

    test('accents only the downbeat when accentDownbeat is on', () {
      final beats = ClickPattern(beatsPerBar: 4).beats();
      expect(beats.map((b) => b.accent).toList(), [true, false, false, false]);
      expect(beats.first, const ClickBeat(beat: 0, accent: true));
    });

    test('accent placement follows the meter — 3/4 vs 5/4', () {
      expect(
        ClickPattern(beatsPerBar: 3).beats().map((b) => b.accent).toList(),
        [true, false, false],
      );
      expect(
        ClickPattern(beatsPerBar: 5).beats().map((b) => b.accent).toList(),
        [true, false, false, false, false],
      );
    });

    test('no beat is accented when accentDownbeat is off', () {
      final beats = ClickPattern(beatsPerBar: 4, accentDownbeat: false).beats();
      expect(beats.every((b) => !b.accent), isTrue);
      expect(beats, hasLength(4));
    });

    test('a meter below 1 clamps to a single downbeat', () {
      final pattern = ClickPattern(beatsPerBar: 0);
      expect(pattern.beatsPerBar, 1);
      expect(pattern.beats(), [const ClickBeat(beat: 0, accent: true)]);
    });

    test('value equality + copyWith', () {
      final a = ClickPattern(beatsPerBar: 4);
      expect(a, ClickPattern(beatsPerBar: 4));
      expect(a, isNot(ClickPattern(beatsPerBar: 3)));
      expect(
        a.copyWith(accentDownbeat: false),
        ClickPattern(beatsPerBar: 4, accentDownbeat: false),
      );
      expect(a.copyWith(beatsPerBar: 7).beatsPerBar, 7);
    });
  });
}
