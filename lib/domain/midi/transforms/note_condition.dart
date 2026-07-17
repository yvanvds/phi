import '../midi_note.dart';
import 'note_comparison.dart';
import 'note_field.dart';

/// A serialisable, declarative predicate over a single [MidiNote] — the data
/// model behind [ConditionalMutingTransform] (issue #109).
///
/// It replaces the bare `bool Function(MidiNote)` callback the transform used
/// to hold: a plain function can't be inspected, edited, or round-tripped, so
/// there was nothing a predicate editor could mutate. This model is pure,
/// immutable, and value-equal, so it edits in place through `copyWith`, survives
/// a param seam, and keeps the chain memoisable.
///
/// The graph's `EdgeCondition` family is deliberately *not* reused here: it
/// evaluates a `GraphEvalContext` (state-machine state / runtime variable),
/// whereas this evaluates a per-note field (pitch / velocity / channel / start).
///
/// A [NoteFieldCondition] is the leaf — one field compared against a threshold;
/// a [NoteConditionGroup] combines child conditions with `all` / `any`. The
/// transform reads [matches] as its *mute* predicate: a note that matches is
/// dropped, so an empty `any` group ([NoteConditionGroup.empty]) matches
/// nothing and is the keep-everything default.
sealed class NoteCondition {
  const NoteCondition();

  /// Whether [note] satisfies this condition.
  bool matches(MidiNote note);
}

/// A leaf predicate: one note [field] compared against a [threshold] by
/// [comparison] — e.g. `velocity < 0.5` (mute soft notes) or `pitch ≥ 72`
/// (mute the top octave).
final class NoteFieldCondition extends NoteCondition {
  const NoteFieldCondition({
    required this.field,
    required this.comparison,
    required this.threshold,
  });

  final NoteField field;
  final NoteComparison comparison;
  final double threshold;

  @override
  bool matches(MidiNote note) => comparison.test(field.read(note), threshold);

  NoteFieldCondition copyWith({
    NoteField? field,
    NoteComparison? comparison,
    double? threshold,
  }) => NoteFieldCondition(
    field: field ?? this.field,
    comparison: comparison ?? this.comparison,
    threshold: threshold ?? this.threshold,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteFieldCondition &&
          other.field == field &&
          other.comparison == comparison &&
          other.threshold == threshold;

  @override
  int get hashCode => Object.hash(field, comparison, threshold);

  @override
  String toString() =>
      'NoteFieldCondition(${field.label} ${comparison.label} $threshold)';
}

/// How a [NoteConditionGroup] folds its child conditions into one verdict.
enum NoteConditionCombinator {
  /// Every child must match (an empty group matches — vacuous truth).
  all('all'),

  /// Any child matches (an empty group matches nothing).
  any('any');

  const NoteConditionCombinator(this.label);

  /// Display label for the predicate editor's combinator picker.
  final String label;
}

/// Combines child [conditions] with a [combinator] — the "small combinator for
/// and/or" the model needs so a predicate can read "mute when *any* of these"
/// or "mute when *all* of these".
///
/// The children are [NoteCondition]s, so a group can nest another group; the
/// predicate editor works one level deep (a flat list of [NoteFieldCondition]
/// leaves), which is all conditional muting needs today. The empty [any] group
/// ([NoteConditionGroup.empty]) matches nothing — the passthrough default a
/// fresh `mute · if` chip carries until the performer adds a condition.
final class NoteConditionGroup extends NoteCondition {
  const NoteConditionGroup({
    this.combinator = NoteConditionCombinator.any,
    this.conditions = const [],
  });

  /// The empty `any` group: matches nothing, so as a mute predicate it drops no
  /// notes. The keep-everything default a catalogue-added chip starts from.
  const NoteConditionGroup.empty() : this();

  final NoteConditionCombinator combinator;
  final List<NoteCondition> conditions;

  @override
  bool matches(MidiNote note) => switch (combinator) {
    NoteConditionCombinator.all => conditions.every((c) => c.matches(note)),
    NoteConditionCombinator.any => conditions.any((c) => c.matches(note)),
  };

  NoteConditionGroup copyWith({
    NoteConditionCombinator? combinator,
    List<NoteCondition>? conditions,
  }) => NoteConditionGroup(
    combinator: combinator ?? this.combinator,
    conditions: conditions ?? this.conditions,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteConditionGroup &&
          other.combinator == combinator &&
          _sameConditions(other.conditions, conditions);

  @override
  int get hashCode => Object.hash(combinator, Object.hashAll(conditions));

  @override
  String toString() => 'NoteConditionGroup(${combinator.label}, $conditions)';
}

/// Element-wise list equality — domain code stays pure Dart, so this stands in
/// for `package:flutter/foundation`'s `listEquals` without a Flutter import.
bool _sameConditions(List<NoteCondition> a, List<NoteCondition> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
