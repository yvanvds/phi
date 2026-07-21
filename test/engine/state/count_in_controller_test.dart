import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/state/count_in_controller.dart';

void main() {
  group('CountInController — scheduling against the engine clock (#263)', () {
    // A hand-driven fake engine clock: `begin`/`tick`/`beatsRemaining` all read
    // this, exactly as they read the real transport's free-running beatPosition.
    late double beat;
    double clock() => beat;

    setUp(() => beat = 0);

    test('bars clamps to 0..maxBars and notifies only on a real change', () {
      final c = CountInController(bars: 9);
      expect(c.bars, CountInController.maxBars);

      var notifications = 0;
      c.addListener(() => notifications++);
      c.bars = 1;
      expect(c.bars, 1);
      c.bars = 1; // no change → no notify
      c.bars = -4; // clamps to 0
      expect(c.bars, 0);
      expect(notifications, 2);
      c.dispose();
    });

    test('a 0-bar setting schedules nothing — the caller starts at once', () {
      final c = CountInController(bars: 0);
      var fired = 0;
      final began = c.begin(
        beatsPerBar: 4,
        beatPosition: clock,
        onComplete: () => fired++,
      );
      expect(began, isFalse);
      expect(c.isCounting, isFalse);
      beat = 100;
      c.tick();
      expect(fired, 0);
      c.dispose();
    });

    // Several meters/tempos: the count completes after exactly bars*beatsPerBar
    // beats regardless of the tempo (tempo lives in the clock the delta reads).
    for (final (bars, beatsPerBar) in const [
      (1, 4),
      (2, 4),
      (1, 3),
      (2, 7),
      (1, 5),
    ]) {
      test('a $bars-bar count at $beatsPerBar/bar fires on the downbeat', () {
        final c = CountInController(bars: bars);
        var fired = 0;
        final target = bars * beatsPerBar.toDouble();
        expect(
          c.begin(
            beatsPerBar: beatsPerBar,
            beatPosition: clock,
            onComplete: () => fired++,
          ),
          isTrue,
        );
        expect(c.isCounting, isTrue);

        // A frame just short of the downbeat: still counting, nothing fired.
        beat = target - 0.01;
        c.tick();
        expect(fired, 0);
        expect(c.isCounting, isTrue);
        expect(c.beatsRemaining, closeTo(0.01, 1e-9));

        // The frame that reaches the downbeat: fires exactly once, count clears.
        beat = target;
        c.tick();
        expect(fired, 1);
        expect(c.isCounting, isFalse);
        expect(c.beatsRemaining, 0);

        // Later frames never re-fire.
        beat = target + 12;
        c.tick();
        expect(fired, 1);
        c.dispose();
      });
    }

    test(
      'the origin is the clock at begin — a running clock still counts N',
      () {
        beat = 41.5; // the clock is already well underway when the count begins
        final c = CountInController(bars: 1);
        var fired = 0;
        c.begin(beatsPerBar: 4, beatPosition: clock, onComplete: () => fired++);

        beat = 41.5 + 3.9; // 3.9 beats in — not yet a full bar
        c.tick();
        expect(fired, 0);

        beat = 41.5 + 4.0; // the downbeat, one bar from the origin
        c.tick();
        expect(fired, 1);
        c.dispose();
      },
    );

    test('cancel aborts a running count without firing (stop during count)', () {
      final c = CountInController(bars: 2);
      var fired = 0;
      c.begin(beatsPerBar: 4, beatPosition: clock, onComplete: () => fired++);
      beat = 3;
      c.cancel();
      expect(c.isCounting, isFalse);

      // The clock races past the old target — nothing fires; the count is gone.
      beat = 999;
      c.tick();
      expect(fired, 0);
      c.dispose();
    });

    test('begin while already counting is a no-op', () {
      final c = CountInController(bars: 1);
      var first = 0, second = 0;
      expect(
        c.begin(beatsPerBar: 4, beatPosition: clock, onComplete: () => first++),
        isTrue,
      );
      expect(
        c.begin(
          beatsPerBar: 4,
          beatPosition: clock,
          onComplete: () => second++,
        ),
        isFalse,
      );
      beat = 4;
      c.tick();
      expect(first, 1);
      expect(second, 0);
      c.dispose();
    });

    test('a non-positive meter schedules nothing', () {
      final c = CountInController(bars: 1);
      expect(
        c.begin(beatsPerBar: 0, beatPosition: clock, onComplete: () {}),
        isFalse,
      );
      expect(c.isCounting, isFalse);
      c.dispose();
    });

    test('a completion callback may re-begin against a clean controller', () {
      final c = CountInController(bars: 1);
      var completes = 0;
      c.begin(
        beatsPerBar: 4,
        beatPosition: clock,
        onComplete: () {
          completes++;
          // On the downbeat the controller is already cleared, so this models a
          // caller starting fresh work without tripping the "already counting"
          // guard.
          expect(c.isCounting, isFalse);
        },
      );
      beat = 4;
      c.tick();
      expect(completes, 1);
      c.dispose();
    });
  });
}
