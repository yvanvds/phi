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
///
/// Targets are **fractional** MIDI pitches (issue #36), so the table can retune
/// the 12 semitones onto a microtonal grid — e.g. mapping the equal-tempered
/// scale onto just-intonation cents. Keys stay integer source pitches; a
/// fractional input never matches a key and so passes through untouched.
class SpectralMappingTransform extends MidiTransform {
  const SpectralMappingTransform({
    required this.table,
    required this.label,
    this.active = true,
  });

  /// Maps a source MIDI pitch (integer semitone) to its fractional
  /// replacement. Missing keys are identity.
  final Map<int, double> table;

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

  /// Carries [table] alongside the base [active]/[label] so the typed table
  /// editor (issue #95) can replace the mapping in place without losing the
  /// chip's toggle or name.
  @override
  SpectralMappingTransform copyWith({
    bool? active,
    String? label,
    Map<int, double>? table,
  }) => SpectralMappingTransform(
    table: table ?? this.table,
    label: label ?? this.label,
    active: active ?? this.active,
  );

  double _map(double pitch) {
    // Only an integer source pitch can name a key; a fractional input is left
    // alone so a microtonal note isn't silently re-quantised by a sparse table.
    final mapped = pitch == pitch.roundToDouble() ? table[pitch.toInt()] : null;
    return (mapped ?? pitch).clamp(0.0, 127.0);
  }
}
