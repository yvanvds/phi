/// Stable identifier for a [TransformNode] inside a [MidiTransformGraph].
///
/// String-backed and client-minted — the transform graph has no native
/// counterpart in `package:yse`, and ids are remapped on load rather than
/// preserved across sessions.
///
/// [TransformNodeId.source] is the reserved sentinel for the clip input: the
/// graph never stores a node under it, but edges may originate from it so the
/// source clip can fan out into more than one branch.
class TransformNodeId {
  const TransformNodeId(this.value);

  /// Mint a fresh id. Monotonic within a process; cross-process uniqueness is
  /// not required because graphs load as snapshots with remapped ids.
  factory TransformNodeId.next() {
    _counter++;
    return TransformNodeId('n$_counter');
  }

  /// The clip input. Edges may start here; no [TransformNode] is stored under
  /// it.
  static const source = TransformNodeId('__source__');

  static int _counter = 0;

  final String value;

  /// Whether this id is the reserved clip-input sentinel.
  bool get isSource => value == source.value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransformNodeId && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'TransformNodeId($value)';
}
