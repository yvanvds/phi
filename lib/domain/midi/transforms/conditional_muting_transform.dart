import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';
import 'note_condition.dart';

/// The evaluated form of a mute predicate: `true` keeps the note, `false` drops
/// it — the shape `List.where` consumes. It used to be the transform's whole
/// model (a bare caller-supplied callback); issue #109 moves the model to a
/// declarative [NoteCondition] and keeps this only as the *evaluated* view of
/// it, so a state-machine read, scene-volume check, or live-coded variable can
/// still stand behind the seam later.
typedef NotePredicate = bool Function(MidiNote note);

/// Drops notes that match [condition], keeping everything else in place.
///
/// This is the boolean seed for what the vision calls conditional muting:
/// gating notes by their own fields today (pitch / velocity / channel / start),
/// by state-machine state, scene volume, or a code variable later. The gate
/// used to be a bare `NotePredicate` callback the caller supplied directly,
/// which nothing could inspect or edit; issue #109 re-backs it with a
/// declarative [NoteCondition] — a pure, immutable value model the typed
/// predicate editor mutates in place. (`VelocityToParameterTransform` made the
/// same callback → model move in issue #108.)
///
/// [condition] is read as a *mute* predicate: a note that matches is dropped.
/// The [NoteConditionGroup.empty] default matches nothing, so a fresh chip is a
/// passthrough the performer makes meaningful by editing alone. Like every
/// transform, evaluation is pure — same note, same verdict — so the chain stays
/// memoisable.
class ConditionalMutingTransform extends MidiTransform {
  const ConditionalMutingTransform({
    required this.condition,
    required this.label,
    this.active = true,
  });

  /// Declarative predicate over a note's fields. Notes that match it are muted.
  final NoteCondition condition;

  @override
  final String label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => MidiTransformKind.struct;

  /// The evaluated keep-form of [condition]: a note survives unless it matches.
  /// Exposed so a caller wanting the plain `List.where` predicate — the old
  /// callback seam — still has one.
  NotePredicate get predicate =>
      (note) => !condition.matches(note);

  @override
  List<MidiNote> apply(List<MidiNote> input) =>
      input.where((n) => !condition.matches(n)).toList(growable: false);

  /// Carries [condition] alongside the base [active]/[label] so the typed
  /// predicate editor (issue #109) can reshape the predicate in place without
  /// losing the chip's toggle or name.
  @override
  ConditionalMutingTransform copyWith({
    bool? active,
    String? label,
    NoteCondition? condition,
  }) => ConditionalMutingTransform(
    condition: condition ?? this.condition,
    label: label ?? this.label,
    active: active ?? this.active,
  );
}
