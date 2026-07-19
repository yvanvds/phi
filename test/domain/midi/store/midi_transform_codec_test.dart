import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/custom_transform_registry.dart';
import 'package:phi/domain/midi/dsl_note.dart';
import 'package:phi/domain/midi/midi_transform.dart';
import 'package:phi/domain/midi/midi_transform_kind.dart';
import 'package:phi/domain/midi/music_scale.dart';
import 'package:phi/domain/midi/scale_tuning.dart';
import 'package:phi/domain/midi/spawn_axis.dart';
import 'package:phi/domain/midi/spawn_source.dart';
import 'package:phi/domain/midi/store/midi_transform_codec.dart';
import 'package:phi/domain/midi/transforms/agent_spawn_transform.dart';
import 'package:phi/domain/midi/transforms/conditional_muting_transform.dart';
import 'package:phi/domain/midi/transforms/custom_transform.dart';
import 'package:phi/domain/midi/transforms/domain_subscription_transform.dart';
import 'package:phi/domain/midi/transforms/humanization_transform.dart';
import 'package:phi/domain/midi/transforms/inversion_transform.dart';
import 'package:phi/domain/midi/transforms/loop_transform.dart';
import 'package:phi/domain/midi/transforms/note_comparison.dart';
import 'package:phi/domain/midi/transforms/note_condition.dart';
import 'package:phi/domain/midi/transforms/note_field.dart';
import 'package:phi/domain/midi/transforms/probabilistic_skip_repeat_transform.dart';
import 'package:phi/domain/midi/transforms/quantization_transform.dart';
import 'package:phi/domain/midi/transforms/reverse_transform.dart';
import 'package:phi/domain/midi/transforms/scale_conformance_transform.dart';
import 'package:phi/domain/midi/transforms/spectral_mapping_transform.dart';
import 'package:phi/domain/midi/transforms/split_voice.dart';
import 'package:phi/domain/midi/transforms/splitting_transform.dart';
import 'package:phi/domain/midi/transforms/stretch_transform.dart';
import 'package:phi/domain/midi/transforms/stub_transform.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/domain/midi/transforms/velocity_curve.dart';
import 'package:phi/domain/midi/transforms/velocity_curve_shape.dart';
import 'package:phi/domain/midi/transforms/velocity_to_parameter_transform.dart';
import 'package:phi/domain/midi/transforms/voice_routing_rule.dart';
import 'package:phi/domain/midi/transforms/voice_routing_transform.dart';
import 'package:phi/domain/time_domains/time_domain.dart';
import 'package:phi/domain/time_domains/time_domain_registry.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  const codec = MidiTransformCodec();

  T roundTrip<T extends MidiTransform>(MidiTransform transform) {
    final encoded = codec.encode(transform);
    expect(encoded['label'], transform.label);
    expect(encoded['active'], transform.active);
    return codec.decode(encoded) as T;
  }

  group('pitch transforms', () {
    test('transpose', () {
      final t = roundTrip<TransposeTransform>(
        const TransposeTransform(semitones: -5, label: 'down 5', active: false),
      );
      expect(t.semitones, -5);
      expect(t.label, 'down 5');
      expect(t.active, isFalse);
    });

    test('scale conformance keeps its cents tuning + tonic', () {
      final t = roundTrip<ScaleConformanceTransform>(
        ScaleConformanceTransform(
          tuning: ScaleTuning.justMajor,
          tonic: 62.5,
          label: 'just',
        ),
      );
      expect(t.tonic, 62.5);
      expect(t.tuning.degreesCents, ScaleTuning.justMajor.degreesCents);
      expect(t.tuning.periodCents, 1200);
    });

    test('inversion', () {
      final t = roundTrip<InversionTransform>(
        const InversionTransform(axis: 60.5, label: 'mirror'),
      );
      expect(t.axis, 60.5);
    });

    test('spectral mapping keeps its integer→fractional table', () {
      final t = roundTrip<SpectralMappingTransform>(
        const SpectralMappingTransform(
          table: {60: 60.5, 67: 66.9},
          label: 'map',
        ),
      );
      expect(t.table, {60: 60.5, 67: 66.9});
    });
  });

  group('time transforms', () {
    test('quantization', () {
      final t = roundTrip<QuantizationTransform>(
        const QuantizationTransform(gravity: 0.6, grid: 0.5, label: 'q'),
      );
      expect(t.gravity, 0.6);
      expect(t.grid, 0.5);
    });

    test('stretch', () {
      final t = roundTrip<StretchTransform>(
        const StretchTransform(factor: 1.5, label: 's'),
      );
      expect(t.factor, 1.5);
    });

    test('humanization keeps its ranges + seed', () {
      final t = roundTrip<HumanizationTransform>(
        const HumanizationTransform(
          label: 'h',
          timeRange: 0.03,
          velocityRange: 0.2,
          seed: 42,
        ),
      );
      expect(t.timeRange, 0.03);
      expect(t.velocityRange, 0.2);
      expect(t.seed, 42);
    });

    test('probabilistic skip/repeat', () {
      final t = roundTrip<ProbabilisticSkipRepeatTransform>(
        const ProbabilisticSkipRepeatTransform(
          label: 'p',
          skipProbability: 0.1,
          repeatProbability: 0.2,
          repeatCount: 3,
          seed: 7,
        ),
      );
      expect(t.skipProbability, 0.1);
      expect(t.repeatProbability, 0.2);
      expect(t.repeatCount, 3);
      expect(t.seed, 7);
    });

    test('domain subscription keeps its domain name', () {
      final t = roundTrip<DomainSubscriptionTransform>(
        const DomainSubscriptionTransform(domainName: 'drum', label: 'dom'),
      );
      expect(t.domainName, 'drum');
      // The resolved domain is re-bound live, so it is null after a decode.
      expect(t.domain, isNull);
    });

    test('domain subscription re-resolves against a session registry', () {
      // With a time-domain registry, decode re-binds the name — the engine's
      // adopt-on-open path (#139), so boundTempo is live again after a reload.
      final registry = TimeDomainRegistry(const [
        TimeDomain(name: 'drum', tempo: 124),
      ]);
      final resolvingCodec = MidiTransformCodec(timeDomains: registry);
      final encoded = codec.encode(
        const DomainSubscriptionTransform(domainName: 'drum', label: 'dom'),
      );
      final decoded =
          resolvingCodec.decode(encoded) as DomainSubscriptionTransform;

      expect(decoded.domainName, 'drum');
      expect(decoded.domain, const TimeDomain(name: 'drum', tempo: 124));
      expect(decoded.boundTempo, 124);
    });

    test('an unknown domain name re-resolves to nothing', () {
      final resolvingCodec = MidiTransformCodec(
        timeDomains: TimeDomainRegistry(const []),
      );
      final encoded = codec.encode(
        const DomainSubscriptionTransform(domainName: 'gone', label: 'dom'),
      );
      final decoded =
          resolvingCodec.decode(encoded) as DomainSubscriptionTransform;

      expect(decoded.domainName, 'gone');
      expect(decoded.domain, isNull);
      expect(decoded.boundTempo, isNull);
    });
  });

  group('voice transforms', () {
    test('voice routing keeps all three rule flavours', () {
      final t = roundTrip<VoiceRoutingTransform>(
        const VoiceRoutingTransform(
          rules: [
            PitchRangeRule(minPitch: 40, maxPitch: 60, voice: 'voice.a'),
            VelocityRangeRule(
              minVelocity: 0.2,
              maxVelocity: 0.8,
              voice: 'voice.b',
            ),
            ScaleDegreeRule(
              scale: MusicScale.dorian,
              tonic: 62,
              degrees: {1, 5},
              voice: 'voice.c',
            ),
          ],
          label: 'route',
        ),
      );
      expect(t.rules, hasLength(3));
      final pitch = t.rules[0] as PitchRangeRule;
      expect([pitch.minPitch, pitch.maxPitch], [40, 60]);
      expect(pitch.voice, 'voice.a');
      final vel = t.rules[1] as VelocityRangeRule;
      expect([vel.minVelocity, vel.maxVelocity], [0.2, 0.8]);
      expect(vel.voice, 'voice.b');
      final deg = t.rules[2] as ScaleDegreeRule;
      expect(deg.scale, MusicScale.dorian);
      expect(deg.tonic, 62);
      expect(deg.degrees, {1, 5});
      expect(deg.voice, 'voice.c');
    });

    test('splitting keeps its split voices', () {
      final t = roundTrip<SplittingTransform>(
        const SplittingTransform(
          voices: [
            SplitVoice(),
            SplitVoice(voice: 'voice.b', pitchOffset: 12, velocityScale: 0.5),
          ],
          label: 'split',
        ),
      );
      expect(t.voices, hasLength(2));
      expect(t.voices[0].voice, isNull);
      expect(t.voices[1].voice, 'voice.b');
      expect(t.voices[1].pitchOffset, 12);
      expect(t.voices[1].velocityScale, 0.5);
    });

    test('velocity → parameter keeps its curve', () {
      final t = roundTrip<VelocityToParameterTransform>(
        const VelocityToParameterTransform(
          parameter: 'filter.cutoff',
          curve: VelocityCurve(
            shape: VelocityCurveShape.exponential,
            valueAt0: 0.1,
            valueAt1: 0.9,
            steps: 6,
          ),
          label: 'vel',
        ),
      );
      expect(t.parameter, 'filter.cutoff');
      expect(t.curve.shape, VelocityCurveShape.exponential);
      expect(t.curve.valueAt0, 0.1);
      expect(t.curve.valueAt1, 0.9);
      expect(t.curve.steps, 6);
    });

    test('agent spawn keeps its three axes + drift', () {
      final t = roundTrip<AgentSpawnTransform>(
        AgentSpawnTransform(
          x: SpawnAxis.of(SpawnSource.pitch),
          y: SpawnAxis.of(SpawnSource.velocity, outMin: -2, outMax: 2),
          z: SpawnAxis.of(SpawnSource.time),
          velocity: Vector3(0, 0, 0.2),
          label: 'spawn',
        ),
      );
      expect(t.x.source, SpawnSource.pitch);
      expect(t.y, SpawnAxis.of(SpawnSource.velocity, outMin: -2, outMax: 2));
      expect(t.z.source, SpawnSource.time);
      expect([t.velocity.x, t.velocity.y, t.velocity.z], [0, 0, 0.2]);
    });
  });

  group('struct transforms', () {
    test('loop keeps repeat count, until, and phase', () {
      final t = roundTrip<LoopTransform>(
        const LoopTransform(
          loopLengthBeats: 16,
          repeatCount: 4,
          phaseOffset: 1.5,
          label: 'loop',
        ),
      );
      expect(t.loopLengthBeats, 16);
      expect(t.repeatCount, 4);
      expect(t.untilBeat, isNull);
      expect(t.phaseOffset, 1.5);
    });

    test('loop with untilBeat set', () {
      final t = roundTrip<LoopTransform>(
        const LoopTransform(loopLengthBeats: 8, untilBeat: 32, label: 'loop'),
      );
      expect(t.untilBeat, 32);
      expect(t.repeatCount, isNull);
    });

    test('reverse', () {
      final t = roundTrip<ReverseTransform>(
        const ReverseTransform(lengthBeats: 8, label: 'rev'),
      );
      expect(t.lengthBeats, 8);
    });

    test('conditional muting keeps its nested condition tree', () {
      final t = roundTrip<ConditionalMutingTransform>(
        const ConditionalMutingTransform(
          condition: NoteConditionGroup(
            combinator: NoteConditionCombinator.all,
            conditions: [
              NoteFieldCondition(
                field: NoteField.velocity,
                comparison: NoteComparison.lessThan,
                threshold: 0.5,
              ),
              NoteFieldCondition(
                field: NoteField.pitch,
                comparison: NoteComparison.greaterOrEqual,
                threshold: 72,
              ),
            ],
          ),
          label: 'mute',
        ),
      );
      final group = t.condition as NoteConditionGroup;
      expect(group.combinator, NoteConditionCombinator.all);
      expect(group.conditions, hasLength(2));
      final first = group.conditions[0] as NoteFieldCondition;
      expect(first.field, NoteField.velocity);
      expect(first.comparison, NoteComparison.lessThan);
      expect(first.threshold, 0.5);
    });

    test('stub keeps its kind', () {
      final t = roundTrip<StubTransform>(
        const StubTransform(
          kind: MidiTransformKind.struct,
          label: 'branch',
          active: false,
        ),
      );
      expect(t.kind, MidiTransformKind.struct);
      expect(t.label, 'branch');
      expect(t.active, isFalse);
    });
  });

  group('custom transforms', () {
    test('encode records the definition name + kind', () {
      final registry = CustomTransformRegistry();
      addTearDown(registry.dispose);
      final definition = registry.register(
        name: 'my_transform',
        transform: (notes) => notes,
        kind: MidiTransformKind.pitch,
      );
      final encoded = codec.encode(
        CustomTransform(definition: definition, label: 'my chip'),
      );
      expect(encoded['type'], 'custom');
      expect(encoded['name'], 'my_transform');
      expect(encoded['kind'], 'pitch');
      expect(encoded['label'], 'my chip');
    });

    test('decode re-links to a live definition when the registry has it', () {
      final registry = CustomTransformRegistry();
      addTearDown(registry.dispose);
      registry.register(
        name: 'my_transform',
        transform: (List<DslNote> notes) => notes,
        kind: MidiTransformKind.pitch,
      );
      final linkingCodec = MidiTransformCodec(customRegistry: registry);
      final encoded = linkingCodec.encode(
        CustomTransform(
          definition: registry['my_transform']!,
          label: 'my chip',
        ),
      );
      final decoded = linkingCodec.decode(encoded);
      expect(decoded, isA<CustomTransform>());
      expect((decoded as CustomTransform).definition.name, 'my_transform');
      expect(decoded.label, 'my chip');
    });

    test('decode falls back to a passthrough stub without a definition', () {
      final encoded = <String, Object?>{
        'type': 'custom',
        'name': 'gone',
        'kind': 'pitch',
        'label': 'gone',
        'active': true,
      };
      // No custom registry wired: the chip stands in as a passthrough stub of
      // the recorded family until the defining block is re-run.
      final decoded = codec.decode(encoded);
      expect(decoded, isA<StubTransform>());
      expect(decoded.kind, MidiTransformKind.pitch);
      expect(decoded.label, 'gone');
    });
  });

  test('an unknown transform type throws a FormatException', () {
    expect(() => codec.decode(const {'type': 'nope'}), throwsFormatException);
  });
}
