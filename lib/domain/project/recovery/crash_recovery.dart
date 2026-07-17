import '../store/project_snapshot.dart';
import '../store/project_store.dart';
import 'command_journal.dart';
import 'recovery_offer.dart';
import 'registry_command_codec.dart';

/// The read/replay side of the command journal — it decides at launch whether a
/// crash left unsaved work and, if so, rebuilds the pre-crash state by
/// **domain-only replay** (design `docs/design/project-registry.md` §7).
///
/// Recovery never re-runs engine calls: it loads the last clean save into a
/// fresh registry, replays the journaled commands onto that pure-Dart tree, and
/// hands the snapshot back so the caller can boot the engine *once* from the
/// final state — exactly as a normal load does. Engine crashes are
/// timing/thread-dependent and are not reproduced by replaying Dart object
/// edits.
///
/// Usage from the (later) project-lifecycle layer:
/// 1. [detect] on open — `null` means a clean journal, nothing to do.
/// 2. otherwise show the recovery dialog over the returned [RecoveryOffer] and
///    call [recover] with the chosen option;
/// 3. boot + save the recovered snapshot, then [resolve] to truncate the journal
///    and clear the sentinel.
///
/// **Crash-loop guard.** [recover] marks the `recovering` sentinel before it
/// replays; if a poison entry crashes the replay, the sentinel survives and the
/// next [detect] reports [RecoveryOffer.crashLoop], steering the performer to
/// *replay to previous* or *skip* instead of re-poisoning.
class CrashRecovery {
  /// Binds recovery to the project's [store] (the last clean save) and its
  /// [journal] (the unsaved tail). [codec] reconstructs each journaled command.
  CrashRecovery({
    required this.store,
    required this.journal,
    this.codec = const RegistryCommandCodec(),
  });

  /// The project store the last clean save is loaded from.
  final ProjectStore store;

  /// The journal holding the commands applied since that save.
  final CommandJournal journal;

  /// Turns each journal entry back into a command to replay.
  final RegistryCommandCodec codec;

  /// Inspects the project at launch. Returns `null` when there is nothing to
  /// recover (no journal); otherwise a [RecoveryOffer] with the unsaved
  /// command count and whether a prior recovery is still marked in progress
  /// (the crash-loop signal).
  Future<RecoveryOffer?> detect() async {
    if (!await journal.hasEntries()) return null;
    final entries = await journal.entries();
    return RecoveryOffer(
      entryCount: entries.length,
      crashLoop: await journal.isRecovering(),
    );
  }

  /// Loads the last clean save and applies the journal per [choice], returning
  /// the recovered snapshot. The caller boots + saves it and then calls
  /// [resolve].
  ///
  /// [RecoveryChoice.skipJournal] returns the clean save untouched.
  /// [RecoveryChoice.replayToPrevious] replays all but the last command (walking
  /// back over a poison edit). Replay marks the `recovering` sentinel first, so
  /// a crash mid-replay is caught by the next [detect].
  Future<ProjectSnapshot> recover(RecoveryChoice choice) async {
    final snapshot = await store.load();
    if (choice == RecoveryChoice.skipJournal) return snapshot;

    await journal.markRecovering();
    final entries = await journal.entries();
    // replayToPrevious stops one short of the tail; an empty journal leaves the
    // count at -1, so the loop simply never runs.
    final count = choice == RecoveryChoice.replayToPrevious
        ? entries.length - 1
        : entries.length;
    for (var i = 0; i < count; i++) {
      codec.decode(entries[i], snapshot.registry).apply();
    }
    return snapshot;
  }

  /// Clears the journal and the `recovering` sentinel after the recovered state
  /// has been saved cleanly (§7). From here the project is back to a known-good
  /// point.
  Future<void> resolve() async {
    await journal.truncate();
    await journal.clearRecovering();
  }
}
