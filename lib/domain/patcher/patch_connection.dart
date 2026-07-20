/// A single cable between two patcher objects: [fromId]'s [outlet] wired to
/// [toId]'s [inlet].
///
/// Objects are addressed by their engine handle id (the `int` the patcher
/// assigns on create), and ports by index — the exact vocabulary the gateway
/// speaks (`docs/design/patcher.md` §3, the gateway generalisation is epic
/// issue 2). Immutable and compared by value so a connect/disconnect gesture
/// and its inverse round-trip cleanly.
class PatchConnection {
  /// Wires [fromId]'s [outlet] to [toId]'s [inlet].
  const PatchConnection({
    required this.fromId,
    required this.outlet,
    required this.toId,
    required this.inlet,
  });

  /// Reads a connection from a decoded `{from, outlet, to, inlet}` map.
  factory PatchConnection.fromJson(Map<String, Object?> json) =>
      PatchConnection(
        fromId: json['from'] as int,
        outlet: json['outlet'] as int,
        toId: json['to'] as int,
        inlet: json['inlet'] as int,
      );

  /// The source object's handle id.
  final int fromId;

  /// The source object's outlet index.
  final int outlet;

  /// The destination object's handle id.
  final int toId;

  /// The destination object's inlet index.
  final int inlet;

  /// The connection as a `{from, outlet, to, inlet}` JSON map.
  Map<String, Object?> toJson() => {
    'from': fromId,
    'outlet': outlet,
    'to': toId,
    'inlet': inlet,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PatchConnection &&
          other.fromId == fromId &&
          other.outlet == outlet &&
          other.toId == toId &&
          other.inlet == inlet);

  @override
  int get hashCode => Object.hash(fromId, outlet, toId, inlet);

  @override
  String toString() => 'PatchConnection($fromId:$outlet -> $toId:$inlet)';
}
