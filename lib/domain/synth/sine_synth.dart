import 'synth_definition.dart';
import 'synth_kind.dart';

/// A `synth.` definition of kind [SynthKind.sine] — the zero-config starter
/// (design `docs/design/racks-and-voices.md` §4).
///
/// The sine synth carries **voice count only**: a fresh project seeds
/// `voice.default` → `synth.sine` → master, and a performer can hear notes
/// before touching a single parameter. A plain, immutable value type.
class SineSynth extends SynthDefinition {
  /// Builds a sine definition with [voiceCount] voices (defaults to 8).
  const SineSynth({this.voiceCount = 8});

  /// Reads a sine definition from a decoded map, defaulting the voice count.
  factory SineSynth.fromJson(Map<String, Object?> json) =>
      SineSynth(voiceCount: (json['voiceCount'] as num?)?.toInt() ?? 8);

  @override
  SynthKind get kind => SynthKind.sine;

  @override
  final int voiceCount;

  SineSynth copyWith({int? voiceCount}) =>
      SineSynth(voiceCount: voiceCount ?? this.voiceCount);

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'voiceCount': voiceCount,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SineSynth && other.voiceCount == voiceCount;

  @override
  int get hashCode => voiceCount.hashCode;

  @override
  String toString() => 'SineSynth(voiceCount: $voiceCount)';
}
