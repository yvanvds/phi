/// Stable identifier for a [PerformanceState] inside a [StateGraph].
///
/// String-backed (rather than int-backed like [PatchNodeId]) because the
/// state machine has no native counterpart in `package:yse` yet — ids are
/// generated client-side via [PerformanceStateId.next]. A counter-based
/// scheme keeps the id stable across renames and serialization round-trips.
class PerformanceStateId {
  const PerformanceStateId(this.value);

  /// Mint a fresh id. Monotonic within a process; uniqueness across
  /// processes is not required because state graphs are loaded as
  /// snapshots — ids are remapped on load, not preserved.
  factory PerformanceStateId.next() {
    _counter++;
    return PerformanceStateId('s$_counter');
  }

  static int _counter = 0;

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PerformanceStateId && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PerformanceStateId($value)';
}
