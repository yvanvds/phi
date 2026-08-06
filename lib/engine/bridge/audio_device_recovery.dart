import 'dart:async';

import 'audio_recovery_status.dart';

/// The **bounded retry** that brings audio back after a total device loss
/// (issue #410, design `docs/design/settings-and-devices.md` §4 "Resilience").
///
/// Phi has to supervise its own recovery, because libyse's `setAutoReconnect`
/// cannot be trusted with it. Measured against the engine sources
/// (`YseEngine/system.cpp`, `device/portaudioDeviceManager.cpp`):
///
/// ```cpp
/// if (callbacks == 0) {
///   currentlyMissedCallbacks++;
///   if (doAutoReconnect && currentlyMissedCallbacks > reconnectDelay) {
///     pause();   // == managerObject::close()
///     resume();  // == addCallback(), which opens Pa_GetDefaultOutputDevice()
///   }
/// } else currentlyMissedCallbacks = 0;
/// ```
///
/// - It **does** arm on a closed engine (no stream means no callbacks, so the
///   gauge only ever climbs) — but what it reopens is `Pa_GetDefaultOutputDevice()`,
///   never the device that was lost, and it drops the chosen buffer size and
///   channel count on the way. It would migrate a set onto the built-in speakers
///   without telling anyone, which is the same lie issue #408 closed.
/// - The gauge is only reset by a callback that *arrives*, never by an attempt,
///   so once armed it runs `close()` + `Pa_OpenStream` on **every** engine
///   control tick — roughly sixty attempts a second, forever, with no backoff.
/// - `reconnectDelay` is compared against a tick count, not milliseconds, so the
///   `delayMs: 1000` the design specified is really ~16 s at the 16 ms control
///   tick (filed as dart-yse #54).
///
/// So boot turns it off and this class takes over: a **fixed, finite schedule**
/// of attempts with growing gaps, each one a real `openDevice` through the
/// gateway — the one recovery libyse genuinely supports from a closed engine,
/// since `closeCurrentDevice()` tears down only the stream and leaves PortAudio,
/// the channel graph and every live handle intact.
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
  /// interface that takes a while to re-enumerate, and finite enough that a
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
