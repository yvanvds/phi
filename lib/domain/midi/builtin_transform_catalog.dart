import 'package:vector_math/vector_math_64.dart';

import 'midi_note.dart';
import 'midi_transform.dart';
import 'midi_transform_kind.dart';
import 'music_scale.dart';
import 'spawn_axis.dart';
import 'spawn_source.dart';
import 'transforms/agent_spawn_transform.dart';
import 'transforms/conditional_muting_transform.dart';
import 'transforms/humanization_transform.dart';
import 'transforms/inversion_transform.dart';
import 'transforms/loop_transform.dart';
import 'transforms/probabilistic_skip_repeat_transform.dart';
import 'transforms/quantization_transform.dart';
import 'transforms/reverse_transform.dart';
import 'transforms/scale_conformance_transform.dart';
import 'transforms/spectral_mapping_transform.dart';
import 'transforms/split_voice.dart';
import 'transforms/splitting_transform.dart';
import 'transforms/stretch_transform.dart';
import 'transforms/transpose_transform.dart';
import 'transforms/velocity_curve.dart';
import 'transforms/velocity_to_parameter_transform.dart';
import 'transforms/voice_routing_transform.dart';

/// One built-in transform the chain `+` menu can add.
///
/// [build] mints a fresh, chain-ready instance with sensible defaults each
/// time it's picked. Transforms whose behaviour is a caller-supplied table or
/// rule-list ([SpectralMappingTransform], [VoiceRoutingTransform],
/// [SplittingTransform], [AgentSpawnTransform], and the scale-tuning of a
/// [ScaleConformanceTransform]) have no meaningful zero-config behaviour, so
/// their default is a **passthrough**: the chip appears and toggles, but leaves
/// the clip unchanged until the performer edits it through the chip's typed
/// parameter editor (issue #95). [VelocityToParameterTransform] joined them once
/// its declarative [VelocityCurve] model landed (issue #108): its
/// [VelocityCurve.identity] default emits identity control events but never
/// touches notes, so it too stays passthrough until the curve is edited. The one
/// still-callback-driven transform ([ConditionalMutingTransform]) stays
/// passthrough until its declarative model lands (#109).
class BuiltinTransform {
  const BuiltinTransform({
    required this.name,
    required this.kind,
    required this.build,
  });

  /// Menu label and the label the added chip carries.
  final String name;

  /// Family the transform belongs to — drives the menu grouping and chip
  /// colour, and matches the transform's own [MidiTransform.kind].
  final MidiTransformKind kind;

  /// Factory for a fresh default instance. Called once per pick, so two chips
  /// added from the same entry are independent objects.
  final MidiTransform Function() build;
}

/// The catalogue of built-in transforms the MIDI chain `+` menu offers,
/// grouped by family. Performer-authored custom transforms (issue #38) are
/// listed alongside these from the `CustomTransformRegistry`.
///
/// Two slots are deliberately *not* offered. The state-machine branch is still
/// a [StubTransform] standing in for infrastructure that doesn't exist yet
/// (issue #35). The drum time-domain subscription is now a real transform
/// ([DomainSubscriptionTransform], issues #60/#61), but the `+` menu can't
/// mint a useful default: it needs a session time-domain registry and a
/// reference tempo to bind to, and neither surface exists yet — so it's added
/// only through the seed chain for now.
abstract final class BuiltinTransformCatalog {
  /// Every built-in, in family order (pitch · time · voice · struct) and, within
  /// a family, in a hand-picked "most-reached-for first" order.
  static final List<BuiltinTransform> entries = [
    // ── pitch ────────────────────────────────────────────────────────────────
    BuiltinTransform(
      name: 'transpose · +12 st',
      kind: MidiTransformKind.pitch,
      build: () =>
          const TransposeTransform(semitones: 12, label: 'transpose · +12 st'),
    ),
    BuiltinTransform(
      name: 'scale · major C',
      kind: MidiTransformKind.pitch,
      build: () => ScaleConformanceTransform.diatonic(
        scale: MusicScale.ionian,
        tonic: 60,
        label: 'scale · major C',
      ),
    ),
    BuiltinTransform(
      name: 'invert · @ 60',
      kind: MidiTransformKind.pitch,
      build: () => const InversionTransform(axis: 60, label: 'invert · @ 60'),
    ),
    BuiltinTransform(
      name: 'spectral · map',
      kind: MidiTransformKind.pitch,
      build: () =>
          const SpectralMappingTransform(table: {}, label: 'spectral · map'),
    ),
    // ── time ─────────────────────────────────────────────────────────────────
    BuiltinTransform(
      name: 'quantize · 1/16',
      kind: MidiTransformKind.time,
      build: () =>
          const QuantizationTransform(gravity: 1, label: 'quantize · 1/16'),
    ),
    BuiltinTransform(
      name: 'stretch · ×2',
      kind: MidiTransformKind.time,
      build: () => const StretchTransform(factor: 2, label: 'stretch · ×2'),
    ),
    BuiltinTransform(
      name: 'humanize',
      kind: MidiTransformKind.time,
      build: () => const HumanizationTransform(label: 'humanize'),
    ),
    BuiltinTransform(
      name: 'skip · repeat',
      kind: MidiTransformKind.time,
      build: () =>
          const ProbabilisticSkipRepeatTransform(label: 'skip · repeat'),
    ),
    // ── voice ────────────────────────────────────────────────────────────────
    BuiltinTransform(
      name: 'route',
      kind: MidiTransformKind.voice,
      build: () => const VoiceRoutingTransform(rules: [], label: 'route'),
    ),
    BuiltinTransform(
      name: 'split',
      kind: MidiTransformKind.voice,
      build: () =>
          const SplittingTransform(voices: [SplitVoice()], label: 'split'),
    ),
    BuiltinTransform(
      name: 'vel → param',
      kind: MidiTransformKind.voice,
      build: () => const VelocityToParameterTransform(
        parameter: 'filter.cutoff',
        curve: VelocityCurve.identity(),
        label: 'vel → param',
      ),
    ),
    BuiltinTransform(
      name: 'spawn · agent',
      kind: MidiTransformKind.voice,
      build: () => AgentSpawnTransform(
        x: SpawnAxis.of(SpawnSource.pitch),
        y: SpawnAxis.of(SpawnSource.velocity),
        z: SpawnAxis.of(SpawnSource.time),
        // Gentle upward drift so spawned agents are live participants that
        // move rather than static points (issue #79). The scene camera's up
        // axis is +Z (`Vector3(0, 0, 1)`), so "up" on screen is +Z, not +Y
        // (issue #89). Scene units / second.
        velocity: Vector3(0, 0, 0.2),
        label: 'spawn · agent',
      ),
    ),
    // ── struct ───────────────────────────────────────────────────────────────
    BuiltinTransform(
      name: 'loop · 4 bars',
      kind: MidiTransformKind.struct,
      build: () => const LoopTransform(
        loopLengthBeats: 16,
        repeatCount: 2,
        label: 'loop · 4 bars',
      ),
    ),
    BuiltinTransform(
      name: 'reverse · 4 bars',
      kind: MidiTransformKind.struct,
      build: () =>
          const ReverseTransform(lengthBeats: 16, label: 'reverse · 4 bars'),
    ),
    BuiltinTransform(
      name: 'mute · if',
      kind: MidiTransformKind.struct,
      build: () => const ConditionalMutingTransform(
        predicate: _keepAll,
        label: 'mute · if',
      ),
    ),
  ];

  /// The built-ins belonging to [kind], in catalogue order.
  static List<BuiltinTransform> forKind(MidiTransformKind kind) =>
      entries.where((e) => e.kind == kind).toList(growable: false);
}

/// Keep-everything predicate — the passthrough default for a fresh
/// [ConditionalMutingTransform].
bool _keepAll(MidiNote note) => true;
