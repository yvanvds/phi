import 'dart:async';

import '../../domain/project/entity_address.dart';
import 'code_evaluator.dart';

/// Mirrors the **live state** into the engine's embedded Python name table —
/// the `state.current` readable of the live-code wiring (design
/// `docs/design/state-graph.md` §5, issue #246).
///
/// The [RealRegistryMirror] counterpart for performance state: where that seam
/// pushes registry *lifecycle* (`phi._sync_create` …), this one pushes the one
/// piece of performance state the `phi` library exposes — the live state's
/// path under `state.` — as `phi._sync_state_current('verse')` scripts. The
/// engine calls [push] on every live-state change (an entry, a load's passive
/// re-seed, a rename remapping the live address), so a script's
/// `state.current` tracks the performance the way the `_sync_*` table calls
/// track the registry.
///
/// Pushes ride the *same* shared [CodeEvaluator] the on-enter scripts run
/// through ([PhiEngine.stateScriptEvaluator]) and are submitted synchronously,
/// so an entry's `state.current` update enters the evaluator's queue **ahead
/// of** the entered state's on-enter script — the script already reads the new
/// value. While no evaluator is wired (a bare engine, or a build without
/// Python) pushes are dropped: there is no interpreter to read the table.
class StateCurrentMirror {
  /// Builds a mirror reading the evaluator through [evaluator] on every push —
  /// the shell wires [PhiEngine.stateScriptEvaluator] late, so the seam is a
  /// getter, never a captured instance.
  StateCurrentMirror(this.evaluator);

  /// The shared evaluator, or `null` while none is wired.
  final CodeEvaluator? Function() evaluator;

  bool _pushedOnce = false;
  EntityAddress? _lastPushed;

  /// Push [state] as the interpreter's `state.current` — its path under
  /// `state.` (`'verse'`, `'songs.verse'`), or a clear for `null`. De-duped:
  /// a repeat of the last pushed address is dropped, so listener-driven calls
  /// cost nothing when the live state did not move. Fire-and-forget like the
  /// registry mirror's pushes — a rejected script surfaces on the evaluator's
  /// own error stream, never here.
  void push(EntityAddress? state) {
    final target = evaluator();
    if (target == null) return; // no interpreter to read it
    if (_pushedOnce && state == _lastPushed) return;
    _pushedOnce = true;
    _lastPushed = state;
    final argument = state == null ? 'None' : "'${state.segments.join('.')}'";
    unawaited(_evaluate(target, 'phi._sync_state_current($argument)'));
  }

  /// Forget the de-dupe memo — after an interpreter re-init (a stop → start
  /// blanks the embedded Python) the next [push] must go through even for an
  /// unchanged live state.
  void reset() {
    _pushedOnce = false;
    _lastPushed = null;
  }

  Future<void> _evaluate(CodeEvaluator target, String source) async {
    try {
      await target.evaluate(source);
    } on Object {
      // A failed push must never bubble up as an unhandled async error; the
      // evaluator surfaces diagnostics on its own events stream.
    }
  }
}
