import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';

/// Remaps each note's pitch through a user-supplied lookup [table].
///
/// Unlike [ScaleConformanceTransform] — which computes the nearest degree of
/// a diatonic mode — this transform imposes an *arbitrary* pitch-to-pitch
/// mapping: harmonic-series stretches, microtonal-rounded tunings, custom
/// scales beyond the diatonic enum, or deliberate re-spellings. The caller
/// owns the musical meaning of the table; the transform just applies it.
///
/// A pitch absent from [table] passes through unchanged, so a sparse table
/// only affects the pitch classes it names. Mapped values are clamped to
/// `[0, 127]` so a table authored loosely can't emit out-of-range MIDI.
class SpectralMappingTransform extends MidiTransform {
  const SpectralMappingTransform({
    required this.table,
    required this.label,
    this.active = true,
  });

  /// Maps a source MIDI pitch to its replacement. Missing keys are identity.
  final Map<int, int> table;

  @override
  final String label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => MidiTransformKind.pitch;

  @override
  List<MidiNote> apply(List<MidiNote> input) => input
      .map((n) => n.copyWith(pitch: _map(n.pitch)))
      .toList(growable: false);

  @override
  SpectralMappingTransform copyWith({bool? active}) => SpectralMappingTransform(
    table: table,
    label: label,
    active: active ?? this.active,
  );

  int _map(int pitch) => (table[pitch] ?? pitch).clamp(0, 127);
}
