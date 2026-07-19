import 'package:vector_math/vector_math_64.dart';

import '../../time_domains/time_domain_registry.dart';
import '../../voice/voice_addresses.dart';
import '../custom_transform_registry.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';
import '../music_scale.dart';
import '../scale_tuning.dart';
import '../spawn_axis.dart';
import '../spawn_source.dart';
import '../transforms/agent_spawn_transform.dart';
import '../transforms/conditional_muting_transform.dart';
import '../transforms/custom_transform.dart';
import '../transforms/domain_subscription_transform.dart';
import '../transforms/humanization_transform.dart';
import '../transforms/inversion_transform.dart';
import '../transforms/loop_transform.dart';
import '../transforms/note_comparison.dart';
import '../transforms/note_condition.dart';
import '../transforms/note_field.dart';
import '../transforms/probabilistic_skip_repeat_transform.dart';
import '../transforms/quantization_transform.dart';
import '../transforms/reverse_transform.dart';
import '../transforms/scale_conformance_transform.dart';
import '../transforms/spectral_mapping_transform.dart';
import '../transforms/split_voice.dart';
import '../transforms/splitting_transform.dart';
import '../transforms/stretch_transform.dart';
import '../transforms/stub_transform.dart';
import '../transforms/transpose_transform.dart';
import '../transforms/velocity_curve.dart';
import '../transforms/velocity_curve_shape.dart';
import '../transforms/velocity_to_parameter_transform.dart';
import '../transforms/voice_routing_rule.dart';
import '../transforms/voice_routing_transform.dart';

/// The polymorphic (de)serialiser for a single [MidiTransform] — the
/// per-transform codec registry issue #135 needs so a clip's interpretation (its
/// transform chain / graph) can persist alongside its source notes.
///
/// A [MidiTransform] is a sealed-in-spirit family of ~20 immutable stages, each
/// with its own fields (a transpose has semitones, a scale-conformance has a
/// cents table, a spawn has three axes). [encode] tags each with a stable
/// `type` string and flattens its fields to a JSON map; [decode] dispatches on
/// that tag and rebuilds the exact stage. The tag is deliberately *not* the Dart
/// class name — a rename must never invalidate saved projects — so the strings
/// here are a frozen wire contract.
///
/// Two families reference things that live outside the note pipeline and so
/// can't be fully rebuilt from JSON alone:
/// - [DomainSubscriptionTransform] persists only its `domainName`; the resolved
///   [TimeDomain] is re-bound live against the session registry, exactly as the
///   seed does. Pass [timeDomains] so [decode] re-resolves the name against it
///   (as the engine does when adopting a loaded clip on project open, issue
///   #139); without one, `boundTempo` stays `null` until the name is re-bound.
/// - [CustomTransform] persists its definition `name` + `kind`; on [decode] it
///   re-links to a live [CustomTransformDefinition] in [customRegistry] when one
///   is registered, else falls back to a passthrough [StubTransform] carrying the
///   name as its label (it re-links once the performer re-runs the defining
///   block — the live-coding hot-reload seam).
class MidiTransformCodec {
  /// Builds a codec. [customRegistry] lets [decode] re-link a persisted
  /// [CustomTransform] to its live definition; `null` (the default, e.g. the
  /// `const` clip codec) decodes customs to passthrough stubs. [timeDomains]
  /// lets [decode] re-resolve a persisted [DomainSubscriptionTransform]'s name
  /// against the session's domains; `null` leaves the subscription unresolved.
  const MidiTransformCodec({this.customRegistry, this.timeDomains});

  /// The catalogue a persisted [CustomTransform] re-binds against on [decode].
  final CustomTransformRegistry? customRegistry;

  /// The session time-domain registry a persisted [DomainSubscriptionTransform]
  /// re-resolves its name against on [decode], or `null` to leave it unresolved.
  final TimeDomainRegistry? timeDomains;

  /// Flattens [transform] to a JSON-compatible map tagged with its `type`.
  Map<String, Object?> encode(MidiTransform transform) {
    final base = <String, Object?>{
      'label': transform.label,
      'active': transform.active,
    };
    return switch (transform) {
      final TransposeTransform t => {
        'type': 'transpose',
        ...base,
        'semitones': t.semitones,
      },
      final ScaleConformanceTransform t => {
        'type': 'scale_conformance',
        ...base,
        'tonic': t.tonic,
        'tuning': _encodeTuning(t.tuning),
      },
      final InversionTransform t => {
        'type': 'inversion',
        ...base,
        'axis': t.axis,
      },
      final SpectralMappingTransform t => {
        'type': 'spectral_mapping',
        ...base,
        'table': {for (final e in t.table.entries) '${e.key}': e.value},
      },
      final QuantizationTransform t => {
        'type': 'quantization',
        ...base,
        'gravity': t.gravity,
        'grid': t.grid,
      },
      final StretchTransform t => {
        'type': 'stretch',
        ...base,
        'factor': t.factor,
      },
      final HumanizationTransform t => {
        'type': 'humanization',
        ...base,
        'timeRange': t.timeRange,
        'velocityRange': t.velocityRange,
        'seed': t.seed,
      },
      final ProbabilisticSkipRepeatTransform t => {
        'type': 'probabilistic_skip_repeat',
        ...base,
        'skipProbability': t.skipProbability,
        'repeatProbability': t.repeatProbability,
        'repeatCount': t.repeatCount,
        'seed': t.seed,
      },
      final VoiceRoutingTransform t => {
        'type': 'voice_routing',
        ...base,
        'rules': t.rules.map(_encodeRule).toList(),
      },
      final SplittingTransform t => {
        'type': 'splitting',
        ...base,
        'voices': t.voices.map(_encodeSplitVoice).toList(),
      },
      final VelocityToParameterTransform t => {
        'type': 'velocity_to_parameter',
        ...base,
        'parameter': t.parameter,
        'curve': _encodeCurve(t.curve),
      },
      final AgentSpawnTransform t => {
        'type': 'agent_spawn',
        ...base,
        'x': _encodeAxis(t.x),
        'y': _encodeAxis(t.y),
        'z': _encodeAxis(t.z),
        'velocity': _encodeVector(t.velocity),
      },
      final LoopTransform t => {
        'type': 'loop',
        ...base,
        'loopLengthBeats': t.loopLengthBeats,
        'repeatCount': t.repeatCount,
        'untilBeat': t.untilBeat,
        'phaseOffset': t.phaseOffset,
      },
      final ReverseTransform t => {
        'type': 'reverse',
        ...base,
        'lengthBeats': t.lengthBeats,
      },
      final ConditionalMutingTransform t => {
        'type': 'conditional_muting',
        ...base,
        'condition': _encodeCondition(t.condition),
      },
      final DomainSubscriptionTransform t => {
        'type': 'domain_subscription',
        ...base,
        'domainName': t.domainName,
      },
      final CustomTransform t => {
        'type': 'custom',
        ...base,
        'name': t.definition.name,
        'kind': t.definition.kind.name,
      },
      final StubTransform t => {'type': 'stub', ...base, 'kind': t.kind.name},
      _ => throw ArgumentError.value(
        transform,
        'transform',
        'no MidiTransformCodec case for ${transform.runtimeType}',
      ),
    };
  }

  /// Rebuilds a [MidiTransform] from the map [encode] produced. Throws a
  /// [FormatException] if `type` is missing or unknown, so a corrupt or
  /// forward-incompatible clip file fails loudly rather than dropping a stage.
  MidiTransform decode(Map<String, Object?> json) {
    final label = json['label'] as String? ?? '';
    final active = json['active'] as bool? ?? true;
    final type = json['type'];
    switch (type) {
      case 'transpose':
        return TransposeTransform(
          semitones: _int(json['semitones']),
          label: label,
          active: active,
        );
      case 'scale_conformance':
        return ScaleConformanceTransform(
          tuning: _decodeTuning(json['tuning']),
          tonic: _double(json['tonic']),
          label: label,
          active: active,
        );
      case 'inversion':
        return InversionTransform(
          axis: _double(json['axis']),
          label: label,
          active: active,
        );
      case 'spectral_mapping':
        return SpectralMappingTransform(
          table: _decodeTable(json['table']),
          label: label,
          active: active,
        );
      case 'quantization':
        return QuantizationTransform(
          gravity: _double(json['gravity']),
          grid: _double(json['grid'], 0.25),
          label: label,
          active: active,
        );
      case 'stretch':
        return StretchTransform(
          factor: _double(json['factor'], 1),
          label: label,
          active: active,
        );
      case 'humanization':
        return HumanizationTransform(
          label: label,
          timeRange: _double(json['timeRange'], 0.02),
          velocityRange: _double(json['velocityRange'], 0.1),
          seed: _int(json['seed']),
          active: active,
        );
      case 'probabilistic_skip_repeat':
        return ProbabilisticSkipRepeatTransform(
          label: label,
          skipProbability: _double(json['skipProbability']),
          repeatProbability: _double(json['repeatProbability']),
          repeatCount: _int(json['repeatCount'], 1),
          seed: _int(json['seed']),
          active: active,
        );
      case 'voice_routing':
        return VoiceRoutingTransform(
          rules: _list(json['rules']).map(_decodeRule).toList(),
          label: label,
          active: active,
        );
      case 'splitting':
        return SplittingTransform(
          voices: _list(json['voices']).map(_decodeSplitVoice).toList(),
          label: label,
          active: active,
        );
      case 'velocity_to_parameter':
        return VelocityToParameterTransform(
          parameter: json['parameter'] as String? ?? '',
          curve: _decodeCurve(json['curve']),
          label: label,
          active: active,
        );
      case 'agent_spawn':
        return AgentSpawnTransform(
          x: _decodeAxis(json['x']),
          y: _decodeAxis(json['y']),
          z: _decodeAxis(json['z']),
          velocity: _decodeVector(json['velocity']),
          label: label,
          active: active,
        );
      case 'loop':
        return LoopTransform(
          loopLengthBeats: _double(json['loopLengthBeats'], 16),
          repeatCount: _nullableInt(json['repeatCount']),
          untilBeat: _nullableDouble(json['untilBeat']),
          phaseOffset: _double(json['phaseOffset']),
          label: label,
          active: active,
        );
      case 'reverse':
        return ReverseTransform(
          lengthBeats: _double(json['lengthBeats'], 16),
          label: label,
          active: active,
        );
      case 'conditional_muting':
        return ConditionalMutingTransform(
          condition: _decodeCondition(json['condition']),
          label: label,
          active: active,
        );
      case 'domain_subscription':
        final domainName = json['domainName'] as String? ?? '';
        final registry = timeDomains;
        if (registry != null) {
          // Re-resolve the name against the session's domains so the adopted
          // subscription binds its clock tempo live (issue #139), exactly as
          // `DomainSubscriptionTransform.resolve` does at seed time.
          return DomainSubscriptionTransform.resolve(
            registry: registry,
            domainName: domainName,
            label: label,
            active: active,
          );
        }
        return DomainSubscriptionTransform(
          domainName: domainName,
          label: label,
          active: active,
        );
      case 'custom':
        return _decodeCustom(json, label: label, active: active);
      case 'stub':
        return StubTransform(
          kind: _kind(json['kind']),
          label: label,
          active: active,
        );
      default:
        throw FormatException('Unknown transform type: "$type".');
    }
  }

  // ── custom ────────────────────────────────────────────────────────────────

  MidiTransform _decodeCustom(
    Map<String, Object?> json, {
    required String label,
    required bool active,
  }) {
    final name = json['name'] as String? ?? label;
    final kind = _kind(json['kind']);
    final definition = customRegistry?[name];
    if (definition != null) {
      return CustomTransform(
        definition: definition,
        active: active,
        label: label,
      );
    }
    // No live definition yet: stand in with a passthrough that keeps the chip's
    // slot, name and family until the performer re-runs the defining block and
    // the registry re-links it.
    return StubTransform(kind: kind, label: label, active: active);
  }

  // ── nested value types ─────────────────────────────────────────────────────

  Map<String, Object?> _encodeTuning(ScaleTuning tuning) => {
    'degreesCents': tuning.degreesCents,
    'periodCents': tuning.periodCents,
  };

  ScaleTuning _decodeTuning(Object? json) {
    final map = _map(json);
    return ScaleTuning(
      degreesCents: _list(
        map['degreesCents'],
      ).map((e) => _double(e)).toList(growable: false),
      periodCents: _double(map['periodCents'], 1200),
    );
  }

  Map<int, double> _decodeTable(Object? json) {
    final map = _map(json);
    return {for (final e in map.entries) int.parse(e.key): _double(e.value)};
  }

  Map<String, Object?> _encodeRule(VoiceRoutingRule rule) => switch (rule) {
    final PitchRangeRule r => {
      'kind': 'pitch_range',
      'minPitch': r.minPitch,
      'maxPitch': r.maxPitch,
      'voice': r.voice,
    },
    final VelocityRangeRule r => {
      'kind': 'velocity_range',
      'minVelocity': r.minVelocity,
      'maxVelocity': r.maxVelocity,
      'voice': r.voice,
    },
    final ScaleDegreeRule r => {
      'kind': 'scale_degree',
      'scale': r.scale.name,
      'tonic': r.tonic,
      'degrees': r.degrees.toList()..sort(),
      'voice': r.voice,
    },
  };

  VoiceRoutingRule _decodeRule(Object? json) {
    final map = _map(json);
    // A malformed rule with no voice degrades to the seeded default rather than
    // dropping the stage — the routing table stays well-formed.
    final voice = map['voice'] as String? ?? VoiceAddresses.defaultVoice;
    switch (map['kind']) {
      case 'pitch_range':
        return PitchRangeRule(
          minPitch: _int(map['minPitch']),
          maxPitch: _int(map['maxPitch']),
          voice: voice,
        );
      case 'velocity_range':
        return VelocityRangeRule(
          minVelocity: _double(map['minVelocity']),
          maxVelocity: _double(map['maxVelocity']),
          voice: voice,
        );
      case 'scale_degree':
        return ScaleDegreeRule(
          scale: _enum(MusicScale.values, map['scale'], MusicScale.ionian),
          tonic: _int(map['tonic']),
          degrees: {for (final d in _list(map['degrees'])) _int(d)},
          voice: voice,
        );
      default:
        throw FormatException('Unknown voice-routing rule: "${map['kind']}".');
    }
  }

  Map<String, Object?> _encodeSplitVoice(SplitVoice voice) => {
    'voice': voice.voice,
    'pitchOffset': voice.pitchOffset,
    'velocityScale': voice.velocityScale,
  };

  SplitVoice _decodeSplitVoice(Object? json) {
    final map = _map(json);
    return SplitVoice(
      voice: map['voice'] as String?,
      pitchOffset: _int(map['pitchOffset']),
      velocityScale: _double(map['velocityScale'], 1),
    );
  }

  Map<String, Object?> _encodeCurve(VelocityCurve curve) => {
    'shape': curve.shape.name,
    'valueAt0': curve.valueAt0,
    'valueAt1': curve.valueAt1,
    'steps': curve.steps,
  };

  VelocityCurve _decodeCurve(Object? json) {
    final map = _map(json);
    return VelocityCurve(
      shape: _enum(
        VelocityCurveShape.values,
        map['shape'],
        VelocityCurveShape.linear,
      ),
      valueAt0: _double(map['valueAt0']),
      valueAt1: _double(map['valueAt1'], 1),
      steps: _int(map['steps'], 4),
    );
  }

  Map<String, Object?> _encodeAxis(SpawnAxis axis) => {
    'source': axis.source.name,
    'inMin': axis.inMin,
    'inMax': axis.inMax,
    'outMin': axis.outMin,
    'outMax': axis.outMax,
  };

  SpawnAxis _decodeAxis(Object? json) {
    final map = _map(json);
    return SpawnAxis(
      source: _enum(SpawnSource.values, map['source'], SpawnSource.pitch),
      inMin: _double(map['inMin']),
      inMax: _double(map['inMax']),
      outMin: _double(map['outMin'], -1),
      outMax: _double(map['outMax'], 1),
    );
  }

  List<double> _encodeVector(Vector3 v) => [v.x, v.y, v.z];

  Vector3 _decodeVector(Object? json) {
    final list = _list(json);
    if (list.length < 3) return Vector3.zero();
    return Vector3(_double(list[0]), _double(list[1]), _double(list[2]));
  }

  Map<String, Object?> _encodeCondition(NoteCondition condition) =>
      switch (condition) {
        final NoteFieldCondition c => {
          'kind': 'field',
          'field': c.field.name,
          'comparison': c.comparison.name,
          'threshold': c.threshold,
        },
        final NoteConditionGroup g => {
          'kind': 'group',
          'combinator': g.combinator.name,
          'conditions': g.conditions.map(_encodeCondition).toList(),
        },
      };

  NoteCondition _decodeCondition(Object? json) {
    final map = _map(json);
    switch (map['kind']) {
      case 'field':
        return NoteFieldCondition(
          field: _enum(NoteField.values, map['field'], NoteField.pitch),
          comparison: _enum(
            NoteComparison.values,
            map['comparison'],
            NoteComparison.lessThan,
          ),
          threshold: _double(map['threshold']),
        );
      case 'group':
        return NoteConditionGroup(
          combinator: _enum(
            NoteConditionCombinator.values,
            map['combinator'],
            NoteConditionCombinator.any,
          ),
          conditions: _list(map['conditions']).map(_decodeCondition).toList(),
        );
      default:
        throw FormatException('Unknown note condition: "${map['kind']}".');
    }
  }

  // ── primitive helpers ───────────────────────────────────────────────────────

  MidiTransformKind _kind(Object? name) =>
      _enum(MidiTransformKind.values, name, MidiTransformKind.struct);

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  static Map<String, Object?> _map(Object? json) =>
      (json as Map).cast<String, Object?>();

  static List<Object?> _list(Object? json) =>
      (json as List?)?.cast<Object?>() ?? const [];

  static int _int(Object? v, [int fallback = 0]) =>
      (v as num?)?.toInt() ?? fallback;

  static int? _nullableInt(Object? v) => (v as num?)?.toInt();

  static double _double(Object? v, [double fallback = 0]) =>
      (v as num?)?.toDouble() ?? fallback;

  static double? _nullableDouble(Object? v) => (v as num?)?.toDouble();
}
