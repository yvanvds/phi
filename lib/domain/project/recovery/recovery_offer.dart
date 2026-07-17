/// How to treat a journal found at launch — the three options the recovery
/// dialog offers (design `docs/design/project-registry.md` §7).
///
/// A monolithic autosave that corrupts offers nothing; the append-only journal
/// degrades gracefully, so a poison edit can be walked back one step instead of
/// losing the whole recovery.
enum RecoveryChoice {
  /// Replay every journaled command onto the last clean save — the normal
  /// recovery of an ordinary crash.
  replayAll,

  /// Replay every command *but the last*, walking back to N−1 to step over an
  /// edit that poisoned the previous recovery attempt.
  replayToPrevious,

  /// Ignore the journal and open the last clean save as-is, discarding the
  /// unsaved tail.
  skipJournal,
}

/// What a launch-time inspection found in a project's journal — the model the
/// recovery dialog renders (design §7, §9).
///
/// A non-null offer means a crash left [entryCount] applied commands unsaved.
/// [crashLoop] is set when the `recovering` sentinel was still present, i.e. a
/// *previous* recovery started but never finished — the signal to lead with
/// [RecoveryChoice.replayToPrevious]/[RecoveryChoice.skipJournal] rather than
/// blindly replaying all again.
class RecoveryOffer {
  /// Builds an offer describing [entryCount] unsaved commands and whether this
  /// is a [crashLoop] (a prior recovery did not finish).
  const RecoveryOffer({required this.entryCount, required this.crashLoop});

  /// How many commands the journal holds since the last clean save.
  final int entryCount;

  /// Whether the `recovering` sentinel was present — a prior recovery attempt
  /// crashed, so replaying everything again may just re-poison.
  final bool crashLoop;

  @override
  bool operator ==(Object other) =>
      other is RecoveryOffer &&
      other.entryCount == entryCount &&
      other.crashLoop == crashLoop;

  @override
  int get hashCode => Object.hash(entryCount, crashLoop);

  @override
  String toString() =>
      'RecoveryOffer(entryCount: $entryCount, crashLoop: $crashLoop)';
}
