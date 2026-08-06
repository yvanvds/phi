import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/audio_device_recovery.dart';

/// The retry *policy* on its own (issue #410) — the part that has to be bounded
/// and observable, exercised without a gateway so the schedule, the budget and
/// the give-up are pinned independently of what an attempt actually does.
void main() {
  const schedule = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  /// Builds a recovery whose attempts succeed only once [succeedFrom] attempts
  /// have been made, recording every attempt time into [at].
  AudioDeviceRecovery build({
    required List<Duration> at,
    required FakeAsync async,
    int? succeedFrom,
    void Function()? onExhausted,
  }) {
    final start = async.elapsed;
    var attempts = 0;
    return AudioDeviceRecovery(
      attempt: () {
        attempts++;
        at.add(async.elapsed - start);
        return succeedFrom != null && attempts >= succeedFrom;
      },
      onExhausted: onExhausted ?? () {},
      schedule: schedule,
    );
  }

  test('retries on the schedule and gives up when the budget is spent', () {
    fakeAsync((async) {
      final at = <Duration>[];
      var exhausted = 0;
      final recovery = build(
        at: at,
        async: async,
        onExhausted: () => exhausted++,
      );

      recovery.arm();
      expect(recovery.status.retrying, isTrue);
      expect(recovery.status.attempts, 0);
      expect(recovery.limit, 3);

      async.elapse(const Duration(seconds: 30));

      // One attempt per schedule entry, at growing gaps — never a hot loop.
      expect(at, const <Duration>[
        Duration(seconds: 1),
        Duration(seconds: 3),
        Duration(seconds: 7),
      ]);
      // And then it stops, exactly once, and says so.
      expect(exhausted, 1);
      expect(recovery.status.retrying, isFalse);
      expect(recovery.status.gaveUp, isTrue);
      expect(recovery.status.attempts, 3);

      // The bound is the whole point: no timer is left behind to fire again.
      async.elapse(const Duration(minutes: 5));
      expect(at, hasLength(3));
      expect(exhausted, 1);

      recovery.dispose();
    });
  });

  test('a successful attempt ends the run — nothing fires afterwards', () {
    fakeAsync((async) {
      final at = <Duration>[];
      var exhausted = 0;
      final recovery = build(
        at: at,
        async: async,
        succeedFrom: 2,
        onExhausted: () => exhausted++,
      );

      recovery.arm();
      async.elapse(const Duration(seconds: 30));

      expect(at, hasLength(2));
      expect(exhausted, 0);
      expect(recovery.status.retrying, isFalse);
      expect(recovery.status.gaveUp, isFalse);

      recovery.dispose();
    });
  });

  test('arming again restarts the budget from the first delay', () {
    fakeAsync((async) {
      final at = <Duration>[];
      var exhausted = 0;
      final recovery = build(
        at: at,
        async: async,
        onExhausted: () => exhausted++,
      );

      recovery.arm();
      async.elapse(const Duration(seconds: 4)); // two attempts in
      expect(at, hasLength(2));

      // The performer picks a device by hand and it fails too: a deliberate act
      // earns a fresh budget rather than inheriting a nearly-spent one.
      at.clear();
      final armedAt = async.elapsed;
      recovery.arm();
      expect(recovery.status.attempts, 0);
      async.elapse(const Duration(seconds: 30));

      // The full schedule again, measured from the re-arm — not the two attempts
      // that were left over.
      expect(at.map((d) => d - armedAt), const <Duration>[
        Duration(seconds: 1),
        Duration(seconds: 3),
        Duration(seconds: 7),
      ]);
      expect(exhausted, 1);

      recovery.dispose();
    });
  });

  test('cancel stops the run and clears the counters', () {
    fakeAsync((async) {
      final at = <Duration>[];
      final recovery = build(at: at, async: async);

      recovery.arm();
      async.elapse(const Duration(seconds: 1));
      expect(at, hasLength(1));
      expect(recovery.status.attempts, 1);

      recovery.cancel();
      expect(recovery.status.retrying, isFalse);
      expect(recovery.status.attempts, 0);
      expect(recovery.status.gaveUp, isFalse);

      async.elapse(const Duration(minutes: 5));
      expect(at, hasLength(1));

      recovery.dispose();
    });
  });

  test('a disposed recovery never arms again', () {
    fakeAsync((async) {
      final at = <Duration>[];
      final recovery = build(at: at, async: async);

      recovery.dispose();
      recovery.arm();
      async.elapse(const Duration(minutes: 5));

      expect(at, isEmpty);
      expect(recovery.status.retrying, isFalse);
    });
  });

  test('the shipped schedule is finite and spans about two minutes', () {
    // The policy this issue committed to, pinned so a later tweak is deliberate:
    // eight attempts, growing gaps, ending inside a couple of minutes.
    const shipped = AudioDeviceRecovery.defaultSchedule;
    expect(shipped, hasLength(8));
    final total = shipped.fold(
      Duration.zero,
      (Duration sum, Duration d) => sum + d,
    );
    expect(total, const Duration(seconds: 120));
    // Monotonically non-decreasing — a backoff, never a tightening loop.
    for (var i = 1; i < shipped.length; i++) {
      expect(shipped[i] >= shipped[i - 1], isTrue);
    }
  });
}
