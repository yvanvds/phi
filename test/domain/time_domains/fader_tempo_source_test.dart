import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/time_domains/fader_tempo_source.dart';

void main() {
  group('FaderTempoSource', () {
    test('rests at zero — no offset, not modulating', () {
      final fader = FaderTempoSource();
      expect(fader.position, 0);
      expect(fader.offset, 0);
      expect(fader.isModulating, isFalse);
    });

    test('offset is position scaled by the bend range', () {
      final fader = FaderTempoSource(bendRange: 40);
      fader.position = 0.5;
      expect(fader.offset, 20);
      expect(fader.isModulating, isTrue);

      fader.position = -1;
      expect(fader.offset, -40);
      expect(fader.isModulating, isTrue);
    });

    test('position clamps to [-1, 1]', () {
      final fader = FaderTempoSource(bendRange: 40);
      fader.position = 5;
      expect(fader.position, 1);
      expect(fader.offset, 40);

      fader.position = -5;
      expect(fader.position, -1);
      expect(fader.offset, -40);
    });

    test('notifies only on a real change', () {
      final fader = FaderTempoSource();
      var notifications = 0;
      fader.addListener(() => notifications++);

      fader.position = 0.3;
      expect(notifications, 1);

      // Re-parking where it already sits notifies nothing.
      fader.position = 0.3;
      expect(notifications, 1);

      // A clamp that lands on the current value is also silent.
      fader.position = 0.3;
      fader.position = 5; // clamps to 1 → a change
      expect(notifications, 2);
      fader.position = 2; // still clamps to 1 → no change
      expect(notifications, 2);
    });

    test('rejects a non-positive bend range', () {
      expect(
        () => FaderTempoSource(bendRange: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => FaderTempoSource(bendRange: -10),
        throwsA(isA<AssertionError>()),
      );
    });

    test('honours an initial position, clamped', () {
      expect(FaderTempoSource(position: 0.25).offset, closeTo(0.25 * 40, 1e-9));
      expect(FaderTempoSource(position: 3).position, 1);
    });
  });
}
