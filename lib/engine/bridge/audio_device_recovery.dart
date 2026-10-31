import 'dart:async';

import 'audio_recovery_status.dart';

/// The **bounded retry** that brings audio back after a total device loss
/// (issue #410, design `docs/design/settings-and-devices.md` §4 "Resilience").
///
/// Phi supervises its own recovery rather than handing it to libyse's
/// `setAutoReconnect` watchdog.
///
/// Under libYSE 2.4 that was forced (issue #410): the watchdog reopened
/// `Pa_GetDefaultOutputDevice()` instead of the device that was lost, dropped
/// the chosen buffer size, read its `delayMs` as a count of control ticks, and
/// once armed retried on every tick with no backoff.
///
/// yse 0.2.0 (libYSE 3.1) fixed all of that — `delayMs` is wall-clock, it
/// reopens the session's last-opened device by name + host with its buffer
/// size, it can be bounded (`maxAttempts`) and polled (`reconnectState`). It
/// is re-evaluated in issue #445 and **still stays off**, because handing over
/// would lose what this class adds and gain nothing it lacks:
///
/// - **Two reach-fors, not one.** An attempt here tries the performer's
///   device and then settles for the platform default *with a notice*
///   (issue #413). The watchdog does one or the other, and its fallback is
///   silent — Phi would have to poll `reconnectState` to find out after the
///   fact.
/// - **No second supervisor on the device.** The watchdog runs inside
///   `update()` on the engine's timer and would race the coordinator's own
///   opens (a manual pick, a revert) for the same stream.
/// - **It still needs Phi.** A replugged device is only found after
///   `refreshDevices()`, which the watchdog does not call — the host has to,
///   while the watchdog reads `reconnecting` (dart-yse docs). Each attempt here
///   is already a refresh + open, so the watchdog would only add a timer.
/// - **Observable on Phi's terms.** [status] drives the status-bar chip and
///   the diagnostics row directly, and the whole run is unit-testable against
///   the fake under `fakeAsync`.
///
/// So boot keeps the watchdog off and this class runs a **fixed, finite
/// schedule** of attempts with growing gaps, each one a device refresh plus a
/// real `openDevice` through the gateway. `closeCurrentDevice()` tears down
/// only the stream and leaves the channel graph and every live handle intact,
/// so a re-open is all recovery needs.
///
/// Bounded and observable by construction: the run is [limit] attempts long,
/// [status] says what is happening at every moment, and when the budget is spent
/// it stops and says so ([AudioRecoveryStatus.gaveUp]) rather than retrying
/// under the floorboards for the rest of the session.
class AudioDeviceRecovery {
  /// Binds a recovery run to its two collaborators. [_attempt] tries to bring a
  /// device up and returns `true` once one is open; [_onExhausted] is called once
  /// when the schedule runs out with nothing open. [_schedule] gives the delay
  /// before each attempt — its length is the attempt budget.
  AudioDeviceRecovery({
    required this._attempt,
    required this._onExhausted,
    this._schedule = defaultSchedule,
  });

  /// Eight attempts over about two minutes: quick enough that a cable pushed
  /// back in within a few seconds is inaudible, patient enough to cover an
  /// interface that takes a while to re-enumerate (or is plugged in only after
  /// Phi started), and finite enough that a
  /// machine with no audio hardware at all stops trying and says so.
  static const List<Duration> defaultSchedule = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 30),
    Duration(seconds: 30),
  ];

  final bool Function() _attempt;
  final void Function() _onExhausted;
  final List<Duration> _schedule;

  Timer? _timer;
  int _attempts = 0;
  bool _gaveUp = false;
  bool _disposed = false;

  /// How many attempts a run is allowed.
  int get limit => _schedule.length;

  /// A snapshot of the run for the surfaces that report it.
  AudioRecoveryStatus get status => AudioRecoveryStatus(
    retrying: _timer != null,
    gaveUp: _gaveUp,
    attempts: _attempts,
    limit: limit,
  );

  /// Starts a fresh run — a full budget from attempt one, cancelling whatever
  /// was scheduled. Called whenever the app newly finds itself with no device
  /// open, including after the performer tried a device by hand and it failed:
  /// a deliberate action deserves a fresh budget.
  void arm() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    _attempts = 0;
    _gaveUp = false;
    if (_schedule.isEmpty) {
      _giveUp();
    } else {
      _scheduleNext();
    }
  }

  /// Stands the run down — a device is open again, or the engine stopped. Resets
  /// the counters, so [status] reads [AudioRecoveryStatus.idle]'s shape rather
  /// than a finished run's.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _attempts = 0;
    _gaveUp = false;
  }

  /// Cancels for good — a disposed recovery ignores [arm].
  void dispose() {
    _disposed = true;
    cancel();
  }

  void _scheduleNext() => _timer = Timer(_schedule[_attempts], _fire);

  void _fire() {
    _timer = null;
    _attempts++;
    // A successful attempt leaves [_timer] null and [_gaveUp] false: the run is
    // simply over. The owner clears the counters through [cancel].
    if (_attempt()) return;
    if (_attempts >= _schedule.length) {
      _giveUp();
      return;
    }
    _scheduleNext();
  }

  void _giveUp() {
    _gaveUp = true;
    _onExhausted();
  }
}
