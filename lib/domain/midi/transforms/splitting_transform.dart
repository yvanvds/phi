import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';
import 'split_voice.dart';

/// Duplicates every note once per entry in [voices] — octave doubling, unison
/// layering across engine voices, velocity-scaled ghost layers.
///
/// The [voices] list *replaces* the source note: the output holds exactly
/// `input.length × voices.length` notes, so a plain `[SplitVoice()]` is the
/// identity and the source survives only if one entry reproduces it. That
/// makes "replace with two octaves" and "keep original plus layer" the same
/// mechanism instead of a keepOriginal flag.
///
/// Copies for one source note stay adjacent in the output (note₀·voice₀,
/// note₀·voice₁, note₁·voice₀ …). Pitch is clamped to `[0, 127]` and
/// velocity to `[0, 1]` so extreme offsets can't emit illegal notes. An
/// empty [voices] list is treated as "not configured yet" and passes notes
/// through unchanged rather than deleting the clip.
class SplittingTransform extends MidiTransform {
  const SplittingTransform({
    required this.voices,
    required this.label,
    this.active = true,
  });

  /// The layers each note is copied onto; order defines output order.
  final List<SplitVoice> voices;

  @override
  final String label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => MidiTransformKind.voice;

  @override
  List<MidiNote> apply(List<MidiNote> input) {
    if (voices.isEmpty) return input;
    return input
        .expand((n) => voices.map((v) => _copy(n, v)))
        .toList(growable: false);
  }

  /// Carries [voices] alongside the base [active]/[label] so the typed
  /// split-voices editor (issue #95) can replace the layer list in place
  /// without losing the chip's toggle or name.
  @override
  SplittingTransform copyWith({
    bool? active,
    String? label,
    List<SplitVoice>? voices,
  }) => SplittingTransform(
    voices: voices ?? this.voices,
    label: label ?? this.label,
    active: active ?? this.active,
  );

  MidiNote _copy(MidiNote note, SplitVoice voice) => note.copyWith(
    voice: voice.voice ?? note.voice,
    pitch: (note.pitch + voice.pitchOffset).clamp(0.0, 127.0),
    velocity: (note.velocity * voice.velocityScale).clamp(0.0, 1.0),
  );
}
