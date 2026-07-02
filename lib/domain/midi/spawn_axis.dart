import 'midi_note.dart';
import 'spawn_source.dart';

/// A single spatial axis of an agent spawn: a [source] note-scalar linearly
/// remapped from its input domain `[inMin, inMax]` into a spatial output
/// range `[outMin, outMax]`.
///
/// The map is clamped — a value outside the input domain lands on the nearest
/// output edge, so a pitch above [inMax] doesn't fly off past [outMax]. When
/// the input domain is degenerate (`inMin == inMax`) every note maps to
/// [outMin], which keeps the axis well-defined rather than dividing by zero.
///
/// Pure and immutable, like every transform-adjacent value: the same note
/// always resolves to the same coordinate, so the spawn mapping stays
/// memoisable alongside the chain.
class SpawnAxis {
  const SpawnAxis({
    required this.source,
    required this.inMin,
    required this.inMax,
    this.outMin = -1.0,
    this.outMax = 1.0,
  });

  /// Convenience constructor picking sensible input domains per [source]:
  /// pitch `0..127`, time `0..16` beats (four 4/4 bars), velocity `0..1`,
  /// channel `0..15`. Callers that need a different span pass the explicit
  /// constructor.
  factory SpawnAxis.of(
    SpawnSource source, {
    double outMin = -1.0,
    double outMax = 1.0,
  }) {
    final (inMin, inMax) = switch (source) {
      SpawnSource.pitch => (0.0, 127.0),
      SpawnSource.time => (0.0, 16.0),
      SpawnSource.velocity => (0.0, 1.0),
      SpawnSource.channel => (0.0, 15.0),
    };
    return SpawnAxis(
      source: source,
      inMin: inMin,
      inMax: inMax,
      outMin: outMin,
      outMax: outMax,
    );
  }

  /// Note dimension this axis reads.
  final SpawnSource source;

  /// Input domain the source scalar is expected to span.
  final double inMin;
  final double inMax;

  /// Spatial output range the input domain maps onto.
  final double outMin;
  final double outMax;

  /// The spatial coordinate [note] maps to along this axis.
  double resolve(MidiNote note) {
    final raw = source.valueOf(note);
    if (inMax == inMin) return outMin;
    final t = ((raw - inMin) / (inMax - inMin)).clamp(0.0, 1.0);
    return outMin + t * (outMax - outMin);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpawnAxis &&
          other.source == source &&
          other.inMin == inMin &&
          other.inMax == inMax &&
          other.outMin == outMin &&
          other.outMax == outMax;

  @override
  int get hashCode => Object.hash(source, inMin, inMax, outMin, outMax);

  @override
  String toString() =>
      'SpawnAxis(${source.name}: [$inMin,$inMax]->[$outMin,$outMax])';
}
