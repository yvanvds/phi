/// Stable identifier for a [PatchNode] inside a single patcher.
///
/// Mirrors the integer id assigned by the native `package:yse` patcher's
/// `PHandle.id`. The engine bridge maintains the int → `PHandle` map; the
/// rest of the app addresses nodes through this typed wrapper so call sites
/// can't accidentally swap a node id for a port index or a channel id.
class PatchNodeId {
  const PatchNodeId(this.value);

  /// Native handle id.
  final int value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PatchNodeId && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PatchNodeId($value)';
}
