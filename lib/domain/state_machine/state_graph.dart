import 'package:flutter/foundation.dart';

import 'performance_state.dart';
import 'performance_state_id.dart';
import 'state_transition.dart';

/// The Dart-side state-graph model — performance states and the directed
/// transitions between them, plus the in-flight transition-drag state the
/// canvas needs.
///
/// Notifies on graph-level changes (add/remove state, add/remove transition,
/// drag-state toggles). Per-state mutable bits (position, name) fire on the
/// [PerformanceState] itself, matching the [PatchGraph] / [PatchNode] split.
///
/// [version] bumps on every notify so painters can do a cheap int
/// comparison in `shouldRepaint`.
class StateGraph extends ChangeNotifier {
  final Map<PerformanceStateId, PerformanceState> _states = {};
  final List<StateTransition> _transitions = [];
  PerformanceStateId? _dragSourceStateId;
  int _version = 0;

  int get version => _version;

  /// Iteration order matches insertion order — but widgets should treat
  /// this as a set.
  Iterable<PerformanceState> get states => _states.values;

  List<StateTransition> get transitions => List.unmodifiable(_transitions);

  /// The state currently being dragged *from* to author a new transition,
  /// if any.
  PerformanceStateId? get dragSourceStateId => _dragSourceStateId;

  PerformanceState? stateById(PerformanceStateId id) => _states[id];

  void addState(PerformanceState state) {
    _states[state.id] = state;
    _bumpAndNotify();
  }

  /// Remove a state and any transitions touching it.
  void removeState(PerformanceStateId id) {
    if (_states.remove(id) == null) return;
    _transitions.removeWhere((t) => t.sourceId == id || t.targetId == id);
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
