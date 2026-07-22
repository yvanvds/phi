import 'dart:async';

import '../../domain/project/entity_address.dart';
import '../../domain/runtime/runtime_variable_registry.dart';
import '../../domain/state_machine/state_transition.dart';
import '../../domain/state_machine/store/state_transition_spec.dart';
import '../../domain/state_machine/store/state_trigger.dart';
import '../bridge/midi_transport.dart';
import 'state_application_notice.dart';
import 'state_machine_controller.dart';

/// The transition **trigger behaviour** (design `docs/design/state-graph.md`
/// §5, §8 decision 3; issue #244): where the persisted [StateTrigger] data
/// actually fires. Manual stays the controller's arm + fire capsule; this
/// scheduler owns the other three kinds:
///
/// - **timed** — "N beats after entering the source state, on domain D".
///   Arming happens on *entry* (the engine chains [onStateEntered] beside the
///   application engine): each timed transition gets a reserved transport
///   clock paced to its `domain.` entity's effective tempo (live override
///   over the authored BPM), the entry beat is captured as the origin, and
///   every frame [_onTick] **queries the engine clock** — the count-in
///   precedent (issue #263): a Dart timer drives the query, never the timing.
///   Leaving the source state first cancels the schedule; a passively
///   re-seeded live state (project load, a deleted live state falling back)
///   was never *entered*, so its timers do not start — recovery lands on the
///   authored state without the performance auto-advancing.
/// - **variable** — fires when a runtime variable takes the matching value,
///   checked on registry *change*, never polled: watchers follow the live
///   state, snapshot the watched values when built, and only a change **to**
///   the match value fires — a variable already matching when the state goes
///   live does not.
/// - **code** — [fireTo], the `phi` control-plane seam (`state.fire("verse")`
///   through `StateMachineControlPort`, issue #233): resolves the live
///   state's outbound transition toward the named state and fires it through
///   the normal path. The seam is kind-agnostic — it is also what any future
///   trigger source can use (design §5).
///
/// **Guard rails.** A fired transition whose target was deleted no-ops with a
/// [StateApplicationNotice]; a timed trigger whose `domain.` clock is gone
/// (or with no clock source wired) skips with one too. Renames follow the
/// registry refactor: [onStateMoved] remaps every armed reference in place,
/// so a rename mid-count keeps the count and a rename mid-watch keeps the
/// watch. Firing is performance, not authorship — nothing here journals.
class StateTriggerScheduler {
  /// Builds a scheduler over [stateMachine]. Timed triggers count on clocks
  /// minted through [createTransport] (`null` — a setup without a MIDI
  /// gateway — degrades every timed trigger to a notice) and pace from
  /// [domainTempo], the effective BPM of a `domain.` entity (`null` when the
  /// domain is unknown). Variable triggers watch [variables]; [onNotice]
  /// receives every degradation.
  StateTriggerScheduler({
    required StateMachineController stateMachine,
    RuntimeVariableRegistry? variables,
    MidiTransport Function({required String clockName, required double tempo})?
    createTransport,
    double? Function(EntityAddress domain)? domainTempo,
    void Function(StateApplicationNotice notice)? onNotice,
    Duration tickInterval = const Duration(milliseconds: 16),
  }) : _stateMachine = stateMachine,
       _variables = variables,
       _createTransport = createTransport,
       _domainTempo = domainTempo ?? ((_) => null),
       _onNotice = onNotice,
       _tickInterval = tickInterval {
    _stateMachine.addListener(_reconcile);
    _variables?.addListener(_onVariablesChanged);
    _rebuildWatchersIfNeeded();
  }

  /// The reserved clock-name prefix timed schedules count on — distinct from
  /// every session, metronome and count-in clock.
  static const String timedClockPrefix = 'phi.state.timed';

  final StateMachineController _stateMachine;
  final RuntimeVariableRegistry? _variables;
  final MidiTransport Function({
    required String clockName,
    required double tempo,
  })?
  _createTransport;
  final double? Function(EntityAddress domain) _domainTempo;
  final void Function(StateApplicationNotice notice)? _onNotice;
  final Duration _tickInterval;

  /// The state whose *entry* armed the current timed schedules, or `null`
  /// when none is armed (nothing entered yet, or the schedules were
  /// cancelled).
  EntityAddress? _entered;

  final List<_TimedSchedule> _schedules = [];

  /// Reserved clocks by name — minted once, kept stopped between arms (the
  /// count-in precedent), disposed with the scheduler.
  final Map<String, MidiTransport> _clocks = {};

  Timer? _timer;

  /// The live state the variable watchers were built for, or `null`.
  EntityAddress? _watchedState;
  List<_VariableWatch> _watchers = const [];

  /// The watched variables' values when the watchers were built (or last
  /// changed) — only a *change* onto the match value fires.
  final Map<String, String?> _lastSeen = {};

  /// The targets of the timed schedules currently *counting* on a clock, in
  /// arming order — observability for tests and surfaces. A schedule that
  /// could not activate (no clock source, missing domain) is excluded.
  List<EntityAddress> get armedTimedTargets => [
    for (final schedule in _schedules)
      if (schedule.clock != null) schedule.target,
  ];

  // ─── entry / exit (chained by the engine) ─────────────────────────────────

  /// A state was *entered* — an explicit fire or `setLive` made it live (the
  /// engine chains this beside the application engine's slice apply). Cancels
  /// the previous entry's timed schedules and arms [state]'s outbound timed
  /// transitions, each counting from the entry beat on its domain clock.
  void onStateEntered(EntityAddress state) {
    _cancelSchedules();
    _entered = state;
    final document = _stateMachine.documentOf(state);
    if (document == null) return;
    for (final spec in document.transitions) {
      final trigger = spec.trigger;
      if (trigger is TimedTrigger) _armSchedule(state, spec.to, trigger);
    }
    _syncTimer();
  }

  /// A `state.` entity moved from [from] to [to] (a rename/regroup — the
  /// engine chains this beside the MIDI guard repoint). Remaps every armed
  /// reference in place, so a rename mid-count keeps the count and a rename
  /// mid-watch keeps the watch. Idempotent.
  void onStateMoved(EntityAddress from, EntityAddress to) {
    final entered = _entered;
    if (entered != null) _entered = _redirect(entered, from, to);
    final watched = _watchedState;
    if (watched != null) _watchedState = _redirect(watched, from, to);
    for (final schedule in _schedules) {
      schedule.source = _redirect(schedule.source, from, to);
      schedule.target = _redirect(schedule.target, from, to);
    }
    _watchers = [
      for (final watch in _watchers)
        _VariableWatch(
          name: watch.name,
          value: watch.value,
          target: _redirect(watch.target, from, to),
        ),
    ];
  }

  /// Cancel every armed timed schedule and forget the entered state — the
  /// engine calls this on a project swap, so a schedule armed in the old
  /// project can never fire into the new one's addresses.
  void cancelAll() {
    _cancelSchedules();
    _entered = null;
    _rebuildWatchersIfNeeded();
  }

  // ─── code trigger — the `phi` control-plane seam ──────────────────────────

  /// Fire the live state's outbound transition toward the state named
  /// [target] — the receiving end of `phi.ctl.state.fire` (design §5, issue
  /// #233). [target] may be a bare leaf name (`verse`), a dotted group path
  /// (`songs.verse`), or a full address (`state.verse`). Kind-agnostic by
  /// design: the seam fires whatever transition points there, and any future
  /// trigger source can ride it. Returns whether a transition fired; every
  /// miss degrades to a notice, never a throw.
  bool fireTo(String target) {
    final live = _stateMachine.activeStateAddress;
    if (live == null) return false;
    StateTransitionSpec? match;
    for (final spec
        in _stateMachine.documentOf(live)?.transitions ??
            const <StateTransitionSpec>[]) {
      if (_matchesTarget(spec.to, target)) {
        match = spec;
        break;
      }
    }
    if (match == null) {
      _notify(
        live,
        'fire "$target" ignored — no transition from ${live.format()} '
        'toward it',
      );
      return false;
    }
    return _fireValidated(live, match.to, kind: 'fired');
  }

  static bool _matchesTarget(EntityAddress to, String target) =>
      to.name == target ||
      to.segments.join('.') == target ||
      to.format() == target;

  // ─── timed schedules ──────────────────────────────────────────────────────

  void _armSchedule(
    EntityAddress source,
    EntityAddress target,
    TimedTrigger trigger,
  ) {
    final schedule = _TimedSchedule(
      source: source,
      target: target,
      beats: trigger.beats,
      domain: trigger.domain,
    );
    _schedules.add(schedule);
    _activate(schedule);
  }

  /// Start [schedule] counting: mint (or reuse) its reserved clock, pace it
  /// to the domain's effective tempo and capture the origin beat. A schedule
  /// that cannot activate — no clock source wired, or its `domain.` clock is
  /// gone — degrades to one notice and stays as a disabled placeholder, so
  /// the positional sync never re-tries (and never re-notices) until its
  /// params are edited or its state is re-entered.
  void _activate(_TimedSchedule schedule) {
    final create = _createTransport;
    if (create == null) {
      _notify(
        schedule.source,
        'timed transition to ${schedule.target.format()} skipped — no clock '
        'source wired',
      );
      return;
    }
    final tempo = _domainTempo(schedule.domain);
    if (tempo == null) {
      _notify(
        schedule.source,
        'timed transition to ${schedule.target.format()} skipped — '
        '${schedule.domain.format()} is missing',
      );
      return;
    }
    final name = '$timedClockPrefix.${schedule.target.format()}';
    final clock = _clocks[name] ??= create(clockName: name, tempo: tempo);
    clock.setTempo(tempo);
    clock.play();
    schedule
      ..clock = clock
      ..origin = clock.beatPosition
      ..appliedTempo = tempo;
  }

  /// One frame: re-pace each armed clock to its domain's current effective
  /// tempo, cancel schedules whose source is no longer live (left without an
  /// entry — a delete's re-seed, an emptied registry), and fire the first
  /// schedule whose clock has counted out its beats.
  void _onTick(Timer _) {
    for (final schedule in List.of(_schedules)) {
      if (_stateMachine.activeStateAddress != schedule.source) {
        _cancel(schedule);
        continue;
      }
      final clock = schedule.clock;
      if (clock == null) continue; // disabled placeholder — never fires
      final tempo = _domainTempo(schedule.domain);
      if (tempo != null && tempo != schedule.appliedTempo) {
        schedule.appliedTempo = tempo;
        clock.setTempo(tempo);
      }
      final elapsed = clock.beatPosition - schedule.origin;
      if (elapsed < schedule.beats - _epsilon) continue;
      _cancel(schedule);
      if (_fireValidated(schedule.source, schedule.target, kind: 'timed')) {
        // The fire re-armed the new entry's schedules; this pass is done.
        break;
      }
    }
    _syncTimer();
  }

  /// Keep the timed schedule set in step with the *entered* state's current
  /// payload — a trigger edit while its source is live arms, re-parameterises
  /// (origin kept: the state was entered once), or cancels in place.
  ///
  /// The sync is **positional**: spec order is stable across a registry
  /// refactor, and a rename rewrites the payload *before* the move event
  /// remaps the armed references — matching by index instead of by target
  /// keeps the running origin, so a rename mid-count keeps the count.
  void _syncSchedules() {
    final entered = _entered;
    if (entered == null) return;
    if (_stateMachine.activeStateAddress != entered) return;
    final document = _stateMachine.documentOf(entered);
    if (document == null) return;
    final timedSpecs = <(EntityAddress, TimedTrigger)>[
      for (final spec in document.transitions)
        if (spec.trigger case final TimedTrigger trigger) (spec.to, trigger),
    ];
    final shared = _schedules.length < timedSpecs.length
        ? _schedules.length
        : timedSpecs.length;
    for (var i = 0; i < shared; i++) {
      final (target, trigger) = timedSpecs[i];
      final schedule = _schedules[i];
      final paramsChanged =
          schedule.beats != trigger.beats || schedule.domain != trigger.domain;
      schedule
        ..target = target
        ..beats = trigger.beats
        ..domain = trigger.domain;
      // A disabled placeholder whose params were just edited gets a fresh
      // activation attempt — editing the trigger is the natural re-arm.
      if (paramsChanged && schedule.clock == null) _activate(schedule);
    }
    while (_schedules.length > timedSpecs.length) {
      _cancel(_schedules.last);
    }
    for (var i = _schedules.length; i < timedSpecs.length; i++) {
      final (target, trigger) = timedSpecs[i];
      _armSchedule(entered, target, trigger);
    }
    _syncTimer();
  }

  void _cancelSchedules() {
    for (final schedule in _schedules) {
      schedule.clock?.stop();
    }
    _schedules.clear();
    _syncTimer();
  }

  void _cancel(_TimedSchedule schedule) {
    schedule.clock?.stop();
    _schedules.remove(schedule);
  }

  void _syncTimer() {
    final needed = _schedules.any((s) => s.clock != null);
    if (needed && _timer == null) {
      _timer = Timer.periodic(_tickInterval, _onTick);
    } else if (!needed && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  // ─── variable watchers ────────────────────────────────────────────────────

  /// Rebuild the watchers when the live state (or its variable-trigger set)
  /// changed. Rebuilding snapshots the watched values, so a variable already
  /// matching when its watcher is built never fires — only a later *change*
  /// onto the match value does. Safe to run on every controller notify: any
  /// variable change was already handled by [_onVariablesChanged] (the
  /// registry notifies synchronously on mutation), so no change is pending
  /// when the snapshot is taken.
  void _rebuildWatchersIfNeeded() {
    final live = _stateMachine.activeStateAddress;
    final next = <_VariableWatch>[];
    if (live != null) {
      for (final spec
          in _stateMachine.documentOf(live)?.transitions ??
              const <StateTransitionSpec>[]) {
        final trigger = spec.trigger;
        if (trigger is VariableTrigger) {
          next.add(
            _VariableWatch(
              name: trigger.name,
              value: trigger.value,
              target: spec.to,
            ),
          );
        }
      }
    }
    if (live == _watchedState && _watchListEquals(_watchers, next)) return;
    _watchedState = live;
    _watchers = next;
    _lastSeen.clear();
    for (final watch in next) {
      _lastSeen[watch.name] = _variables?.byName(watch.name)?.current;
    }
  }

  void _onVariablesChanged() {
    final registry = _variables;
    if (registry == null) return;
    final source = _watchedState;
    for (final watch in List.of(_watchers)) {
      final current = registry.byName(watch.name)?.current;
      if (current == _lastSeen[watch.name]) continue;
      _lastSeen[watch.name] = current;
      if (current != watch.value || source == null) continue;
      if (_fireValidated(source, watch.target, kind: 'variable')) return;
    }
  }

  static bool _watchListEquals(List<_VariableWatch> a, List<_VariableWatch> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ─── shared ───────────────────────────────────────────────────────────────

  /// On every controller notify: keep the watchers on the live state and the
  /// timed schedules in step with the entered state's payload. A live-state
  /// mismatch against [_entered] is *not* acted on here — a rename remaps it
  /// through [onStateMoved] within the same synchronous pass, and a genuine
  /// exit is either an entry (which re-arms) or is cleaned up by the next
  /// tick's source-still-live check.
  void _reconcile() {
    _rebuildWatchersIfNeeded();
    _syncSchedules();
  }

  /// Validate and fire [source] → [target] through the controller's normal
  /// path. The guard rail (design §5): a target deleted since the trigger was
  /// authored no-ops with a notice; a stale source (no longer live) or a
  /// removed transition no-ops silently — its schedule was already cancelled.
  bool _fireValidated(
    EntityAddress source,
    EntityAddress target, {
    required String kind,
  }) {
    if (_stateMachine.activeStateAddress != source) return false;
    if (_stateMachine.triggerOf(source, target) == null) return false;
    if (_stateMachine.documentOf(target) == null) {
      _notify(
        source,
        '$kind transition to ${target.format()} dropped — target deleted',
      );
      return false;
    }
    _stateMachine.fire(StateTransition(source: source, target: target));
    return true;
  }

  void _notify(EntityAddress state, String message) =>
      _onNotice?.call(StateApplicationNotice(state: state, message: message));

  static EntityAddress _redirect(
    EntityAddress address,
    EntityAddress from,
    EntityAddress to,
  ) {
    if (address == from) return to;
    if (!address.isDescendantOf(from)) return address;
    return EntityAddress(
      kind: address.kind,
      segments: [
        ...to.segments,
        ...address.segments.sublist(from.segments.length),
      ],
    );
  }

  /// Detach from the controller and the variable registry, cancel the frame
  /// timer, and dispose every reserved clock.
  void dispose() {
    _stateMachine.removeListener(_reconcile);
    _variables?.removeListener(_onVariablesChanged);
    _timer?.cancel();
    _timer = null;
    _schedules.clear();
    for (final clock in _clocks.values) {
      clock.dispose();
    }
    _clocks.clear();
  }

  static const double _epsilon = 1e-9;
}

/// One armed timed transition: fire [source] → [target] once [clock] has
/// advanced [beats] past [origin]. Mutable — a payload edit re-parameterises
/// it in place and a rename remaps its addresses. [clock] is `null` for a
/// disabled placeholder (activation degraded to a notice); it never fires.
class _TimedSchedule {
  _TimedSchedule({
    required this.source,
    required this.target,
    required this.beats,
    required this.domain,
  });

  EntityAddress source;
  EntityAddress target;
  double beats;
  EntityAddress domain;
  MidiTransport? clock;
  double origin = 0;
  double appliedTempo = 0;
}

/// One armed variable watcher: fire toward [target] when the variable named
/// [name] *changes to* [value].
class _VariableWatch {
  const _VariableWatch({
    required this.name,
    required this.value,
    required this.target,
  });

  final String name;
  final String value;
  final EntityAddress target;

  @override
  bool operator ==(Object other) =>
      other is _VariableWatch &&
      other.name == name &&
      other.value == value &&
      other.target == target;

  @override
  int get hashCode => Object.hash(name, value, target);
}
