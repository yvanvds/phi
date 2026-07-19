import 'package:flutter_test/flutter_test.dart';
import 'package:phi/surfaces/midi/snap_grid.dart';

void main() {
  group('SnapGrid', () {
    test('lists off · 1/1 … 1/32 · triplets in order', () {
      expect(SnapGrid.options.map((o) => o.label).toList(), [
        'off',
        '1/1',
        '1/2',
        '1/4',
        '1/8',
        '1/16',
        '1/32',
        '1/8T',
        '1/16T',
      ]);
    });

    test('values are beats with a quarter note = 1 beat', () {
      expect(SnapGrid.off, 0);
      expect(SnapGrid.whole, 4);
      expect(SnapGrid.half, 2);
      expect(SnapGrid.quarter, 1);
      expect(SnapGrid.eighth, 0.5);
      expect(SnapGrid.sixteenth, 0.25);
      expect(SnapGrid.thirtySecond, 0.125);
    });

    test('triplets are the exact thirds', () {
      expect(SnapGrid.eighthTriplet, 1 / 3);
      expect(SnapGrid.sixteenthTriplet, 1 / 6);
      // Three eighth-triplets fill a quarter (one beat); six sixteenth-triplets
      // fill a beat too — the defining property of a triplet grid.
      expect(SnapGrid.eighthTriplet * 3, closeTo(1, 1e-12));
      expect(SnapGrid.sixteenthTriplet * 6, closeTo(1, 1e-12));
    });

    test('every option value is unique (picker match is unambiguous)', () {
      final values = SnapGrid.options.map((o) => o.value).toSet();
      expect(values, hasLength(SnapGrid.options.length));
    });
  });
}
