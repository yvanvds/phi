import '../../domain/project/entity_address.dart';
import '../../domain/state_machine/slices/mix_slice_entry.dart';
import '../../domain/state_machine/slices/state_slice_resolution.dart';
import '../../domain/state_machine/slices/tempo_slice_entry.dart';
import '../bridge/code_evaluator.dart';
import 'state_application_notice.dart';
import 'state_slice_applier.dart';

/// The state **application engine** (design `docs/design/state-graph.md` §4,
/// §8 decision 2; issue #243): entering a state applies its captured slices
/// through the owning controllers in fixed order — **variables → tempos → mix
/// → clips → on-enter script**. Structure first, sound last, script over
/// everything.
///
/// **Journal-free by design.** Application changes performance state only: mix
/// levels apply as live (engine-ramped) values, clip play/stop goes through
/// the sessions, variables through the runtime registry, tempos through the
/// clock binding. No payload is written and nothing enters the journal — this
/// class holds no registry and no command recorder, so a crash-recovery
/// replay lands on the *authored* state, never mid-performance.
///
/// **Graceful degradation everywhere.** The caller hands in the
/// [StateSliceResolution] (dangling referents already partitioned out); this
/// engine applies the applicable remainder and surfaces every skip through
/// [onNotice]: missing referents, undefined variables, unstartable clips, a
/// missing on-enter `code.` entity, a failed evaluation. A throwing
/// controller degrades to a notice too — entering a state never crashes the
/// performance.
///
/// The slice categories go through a [StateSliceApplier] and the script
/// through a [CodeEvaluator], both injected — faked in tests (the cross-epic
/// seams of #183 and #228), wired to the real controllers by the engine.
class StateApplicationEngine {
  /// Builds an application engine over [_applier], resolving on-enter scripts
  /// through [_scriptSourceOf] and evaluating them through [_evaluator] (read
  /// per entry, so the shell can wire it late). [_onNotice] receives every
  /// degradation notice.
  StateApplicationEngine({
    required this._applier,
    required this._evaluator,
    required this._scriptSourceOf,
    this._onNotice,
  });

  final StateSliceApplier _applier;

  /// The evaluator on-enter scripts run through — `null` when none is wired
  /// (the script then skips with a notice).
  final CodeEvaluator? Function() _evaluator;

  /// Resolves a `code.` entity address to its stored source, or `null` when
  /// no such script exists — the missing-reference seam (design §4).
  final String? Function(EntityAddress code) _scriptSourceOf;

  final void Function(StateApplicationNotice notice)? _onNotice;

  /// Apply the entered [state]: the [resolution]'s applicable slices in the
  /// fixed category order, then the [onEnter] script. Uncaptured categories
  /// are left untouched (the no-hierarchy principle: a state constrains
  /// exactly what was captured); a captured-but-empty category still applies
  /// ("no clips playing" stops the playing set). The returned future completes
  /// when the script evaluation (if any) has been accepted or degraded.
  Future<void> enterState({
    required EntityAddress state,
    required StateSliceResolution resolution,
    EntityAddress? onEnter,
  }) async {
    if (resolution.hasMissing) {
      final missing = resolution.missing.map((a) => a.format()).join(', ');
      _notify(state, 'skipped deleted referents: $missing');
    }
    final slices = resolution.applicable;

    // 1. Variables — MIDI-graph branches re-route before anything sounds.
    final variables = slices.variables;
    if (variables != null) {
      _guarded(state, 'variables slice', () {
        final skipped = <String>[];
        for (final entry in variables.entries) {
          if (!_applier.applyVariable(entry.key, entry.value)) {
            skipped.add(entry.key);
          }
        }
        if (skipped.isNotEmpty) {
          _notify(
            state,
            'skipped variables (undefined name or value): '
            '${skipped.join(', ')}',
          );
        }
      });
    }

    // 2. Tempos — the domain clocks re-pace.
    for (final entry in slices.tempos ?? const <TempoSliceEntry>[]) {
      _guarded(state, 'tempo of ${entry.domain.format()}', () {
        _applier.applyTempo(entry.domain, entry.bpm);
      });
    }

    // 3. Mix — live levels, ramped by the engine's fades.
    for (final entry in slices.mix ?? const <MixSliceEntry>[]) {
      _guarded(state, 'mix level of ${entry.bus.format()}', () {
        _applier.applyMix(entry.bus, volume: entry.volume, muted: entry.muted);
      });
    }

    // 4. Clips — play/stop to match the captured set, sound last.
    final clips = slices.clips;
    if (clips != null) {
      _guarded(state, 'clips slice', () {
        final skipped = _applier.applyClips(clips);
        if (skipped.isNotEmpty) {
          _notify(
            state,
            'skipped clips with no playable document: '
            '${skipped.map((a) => a.format()).join(', ')}',
          );
        }
      });
    }

    // 5. On-enter script — over everything.
    if (onEnter != null) await _runOnEnter(state, onEnter);
  }

  /// Evaluate the on-enter [script] through the ordinary evaluator. Every
  /// degradation — missing `code.` entity, no evaluator wired, a rejected
  /// chunk, an evaluator throw — becomes a notice, never a crash.
  Future<void> _runOnEnter(EntityAddress state, EntityAddress script) async {
    final source = _scriptSourceOf(script);
    if (source == null) {
      _notify(state, 'on-enter script ${script.format()} is missing — skipped');
      return;
    }
    final evaluator = _evaluator();
    if (evaluator == null) {
      _notify(
        state,
        'on-enter script ${script.format()} skipped — no evaluator wired',
      );
      return;
    }
    try {
      final outcome = await evaluator.evaluate(source);
      if (!outcome.ok) {
        _notify(
          state,
          'on-enter script ${script.format()} failed: '
          '${outcome.error ?? 'rejected'}',
        );
      }
    } on Object catch (error) {
      _notify(state, 'on-enter script ${script.format()} failed: $error');
    }
  }

  /// Run one category application, degrading any unexpected throw to a
  /// notice so the remaining categories still apply.
  void _guarded(EntityAddress state, String what, void Function() run) {
    try {
      run();
    } on Object catch (error) {
      _notify(state, '$what failed: $error');
    }
  }

  void _notify(EntityAddress state, String message) =>
      _onNotice?.call(StateApplicationNotice(state: state, message: message));
}
