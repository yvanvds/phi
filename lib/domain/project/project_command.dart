import 'entity_address.dart';

/// One undoable, journalable mutation — the unit every surface's [UndoScope]
/// holds and the future journal (#122) replays. Design record:
/// `docs/design/project-registry.md` §6.
///
/// The design sketches [apply]/[revert] as taking a `ProjectRegistry`; in
/// practice a command **binds its own target at construction** — the registry
/// it mutates, or, for the folded MIDI clip editor, the `MidiClip` it edits —
/// and [apply]/[revert] take no argument. That one generalisation lets a single
/// [UndoScope] and the *undo-follows-focus* router serve every surface, clip
/// editing included, before the clip itself becomes a registry entity (epic
/// issue 7).
///
/// Contract:
/// - [apply] performs the mutation and records whatever [revert] needs to undo
///   it exactly; [revert] is the precise inverse. A scope replays commands
///   strictly LIFO, so a command may capture indices/state during [apply] and
///   trust them at [revert].
/// - [entitiesTouched] is the set of addresses this command creates, deletes or
///   changes — the input to save/autosave dirty-tracking (#121) and journal
///   bookkeeping (#122). It may be empty when the command's target is not yet a
///   registry entity (the pre-migration clip editor).
/// - [toJson] serialises the command for the journal; [label] names it for a
///   menu ("rename voice.bells").
abstract class ProjectCommand {
  /// A short, human-readable name for a menu or status line.
  String get label;

  /// The addresses this command creates, deletes or changes.
  Set<EntityAddress> get entitiesTouched;

  /// Performs the mutation, recording whatever [revert] needs to undo it.
  void apply();

  /// The precise inverse of [apply].
  void revert();

  /// The command as a JSON map, for the recovery journal (§7).
  Map<String, Object?> toJson();
}
