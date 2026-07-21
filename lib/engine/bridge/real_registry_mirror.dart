import 'dart:async';

import '../../domain/project/entity_address.dart';
import 'code_evaluator.dart';
import 'registry_mirror.dart';

/// The live [RegistryMirror] — it turns registry lifecycle changes into
/// `phi._sync_*(...)` scripts and pushes them through a [CodeEvaluator], so the
/// engine's embedded Python name table tracks the Dart registry (design
/// `docs/design/live-coding.md` §3, issue #231).
///
/// This replaces the `NoOpRegistryMirror` seam the registry epic shipped. Each
/// incremental event maps 1:1 onto a `phi` sync function the library already
/// exposes (issue #230):
///
/// | mirror event          | pushed script                                |
/// |-----------------------|----------------------------------------------|
/// | [onCreate]            | `phi._sync_create('<addr>')`                 |
/// | [onRename]            | `phi._sync_rename('<from>', '<to>')`         |
/// | [onRegroup]           | `phi._sync_regroup('<from>', '<to>')`        |
/// | [onDelete]            | `phi._sync_delete('<addr>')`                 |
/// | [syncAll]             | `phi._sync_replace(['<a>', '<b>', …])`       |
///
/// **Ordering.** Pushes ride the *same* [CodeEvaluator] the Code surface runs
/// user blocks on, and each is submitted synchronously in event order, so they
/// enter the evaluator's queue ahead of any later user evaluation — a script run
/// right after a rename already sees the renamed table (design §3). The mirror
/// never awaits between pushes (that could let a user block jump the queue); it
/// only guards the returned future so a rejected push can't surface as an
/// unhandled async error — the evaluator's own error stream carries diagnostics.
///
/// **Kinds.** Every registry kind is forwarded verbatim; the `phi` library
/// ignores the ones it does not model (`synth.`, …), so the mirror needs no
/// per-kind knowledge (issue #231).
///
/// The mirror does **not** own the evaluator — the shell does — so it never
/// disposes it.
class RealRegistryMirror implements RegistryMirror {
  /// Pushes `_sync_*` scripts through [_evaluator] — pass the same evaluator the
  /// Code surface uses so pushes and user blocks share one ordered queue.
  RealRegistryMirror(this._evaluator);

  final CodeEvaluator _evaluator;

  @override
  void onCreate(EntityAddress address) =>
      _push("phi._sync_create('${address.format()}')");

  @override
  void onDelete(EntityAddress address) =>
      _push("phi._sync_delete('${address.format()}')");

  @override
  void onRename(EntityAddress from, EntityAddress to) =>
      _push("phi._sync_rename('${from.format()}', '${to.format()}')");

  @override
  void onRegroup(EntityAddress from, EntityAddress to) =>
      _push("phi._sync_regroup('${from.format()}', '${to.format()}')");

  @override
  void syncAll(Iterable<EntityAddress> addresses) {
    final list = addresses.map((a) => "'${a.format()}'").join(', ');
    _push('phi._sync_replace([$list])');
  }

  /// Submit [source] to the evaluator immediately (preserving submission order)
  /// and swallow the outcome — a sync push is fire-and-forget from the mirror's
  /// side.
  void _push(String source) {
    unawaited(_evaluate(source));
  }

  Future<void> _evaluate(String source) async {
    try {
      await _evaluator.evaluate(source);
    } on Object {
      // A failed sync push must never bubble up as an unhandled async error;
      // the evaluator surfaces diagnostics on its own events stream.
    }
  }
}
