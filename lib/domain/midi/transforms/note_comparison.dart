/// A numeric comparison a [NoteFieldCondition] applies between a note field's
/// value and a threshold (issue #109).
///
/// The six standard orderings, so a predicate can gate on "softer than",
/// "at least", "exactly", and so on. Equality (`equal` / `notEqual`) is offered
/// for completeness; on a continuous field (velocity, fractional pitch) it is a
/// sharp edge the performer wields deliberately, while the ordering comparisons
/// are the everyday tools. The [label] is the glyph the editor's comparison
/// picker shows.
enum NoteComparison {
  lessThan('<'),
  lessOrEqual('≤'),
  equal('='),
  notEqual('≠'),
  greaterOrEqual('≥'),
  greaterThan('>');

  const NoteComparison(this.label);

  /// The glyph the predicate editor's comparison picker shows.
  final String label;

  /// Whether [value] stands in this relation to [threshold].
  bool test(double value, double threshold) => switch (this) {
    NoteComparison.lessThan => value < threshold,
    NoteComparison.lessOrEqual => value <= threshold,
    NoteComparison.equal => value == threshold,
    NoteComparison.notEqual => value != threshold,
    NoteComparison.greaterOrEqual => value >= threshold,
    NoteComparison.greaterThan => value > threshold,
  };
}
