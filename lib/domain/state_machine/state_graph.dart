import 'package:flutter/foundation.dart';

import 'performance_state.dart';
import 'performance_state_id.dart';
import 'state_transition.dart';

/// The Dart-side state-graph model — performance states and the directed
/// transitions between them, plus the in-flight transition-drag state the
/// canvas needs.
///
/// Notifies on graph-level changes (add/remove state, add/remove
/// transition, arm/fire, active-state change, drag-state toggles).
/// Per-state mutable bits (position, name) fire on the
/// [PerformanceState] itself, matching the [PatchGraph] / [PatchNode]
/// split.
///
/// [version] bumps on every notify so painters can do a cheap int
/// comparison in `shouldRepaint`.
class StateGraph extends ChangeNotifier {
  final Map<PerformanceStateId, PerformanceState> _states = {};
  final List<StateTransition> _transitions = [];
  PerformanceStateId? _dragSourceStateId;
  PerformanceStateId? _activeStateId;
  int _version = 0;

  int get version => _version;

  /// Iteration order matches insertion order — but widgets should treat
  /// this as a set.
  Iterable<PerformanceState> get states => _states.values;

  List<StateTransition> get transitions => List.unmodifiable(_transitions);

  /// The state currently being dragged *from* to author a new transition,
  /// if any.
  PerformanceStateId? get dragSourceStateId => _dragSourceStateId;

  /// The state currently "live" — exactly one (or none) at a time. The
  /// node renders the fuchsia `● LIVE` capsule when its id matches.
  PerformanceStateId? get activeStateId => _activeStateId;

  PerformanceState? stateById(PerformanceStateId id) => _states[id];

  void addState(PerformanceState state) {
    _states[state.id] = state;
    _bumpAndNotify();
  }

  /// Remove a state and any transitions touching it. Clears the active
  /// pointer if it referred to [id].
  void removeState(PerformanceStateId id) {
    if (_states.remove(id) == null) return;
    _transitions.removeWhere((t) => t.sourceId == id || t.targetId == id);
    if (_activeStateId == id) _activeStateId = null;
    _bumpAndNotify();
  }

  /// Add [transition] unless it would be a self-loop or already exists.
  /// Returns whether it was inserted.
  bool addTransition(StateTransition transition) {
    if (transition.sourceId == transition.targetId) return false;
    if (_transitions.contains(transition)) return false;
    _transitions.add(transition);
    _bumpAndNotify();
    return true;
  }

  void removeTransition(StateTransition transition) {
    if (!_transitions.remove(transition)) return;
    _bumpAndNotify();
  }

  /// Mark [id] as live, or clear (pass `null`) so no state is live.
  /// No-op if [id] is unknown or already active.
  void setActive(PerformanceStateId? id) {
    if (id != null && !_states.containsKey(id)) return;
    if (_activeStateId == id) return;
    _activeStateId = id;
    _bumpAndNotify();
  }

  /// Flip the [StateTransition.armed] flag on the in-graph instance
  /// equal to [transition] (matched by `(sourceId, targetId)`). Returns
  /// whether a matching transition was found.
  bool toggleArmed(StateTransition transition) {
    final i = _transitions.indexOf(transition);
    if (i < 0) return false;
    final existing = _transitions[i];
    _transitions[i] = existing.copyWith(armed: !existing.armed);
    _bumpAndNotify();
    return true;
  }

  /// Fire [transition]: mark its `targetId` active and clear every arm
  /// on the graph. No-op if [transition] is unknown. Returns whether the
  /// transition was found and fired.
  bool fire(StateTransition transition) {
    final i = _transitions.indexOf(transition);
    if (i < 0) return false;
    final target = _transitions[i].targetId;
    for (var j = 0; j < _transitions.length; j++) {
      if (_transitions[j].armed) {
        _transitions[j] = _transitions[j].copyWith(armed: false);
      }
    }
    _activeStateId = target;
    _bumpAndNotify();
    return true;
  }

  /// Begin a drag-to-create-transition gesture from [from].
  void beginTransitionDrag(PerformanceStateId from) {
    _dragSourceStateId = from;
    _bumpAndNotify();
  }

  /// End the in-flight transition drag, whether or not it landed on a target.
  void endTransitionDrag() {
    if (_dragSourceStateId == null) return;
    _dragSourceStateId = null;
    _bumpAndNotify();
  }

  void _bumpAndNotify() {
    _version++;
    notifyListeners();
  }
}
