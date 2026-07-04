import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/music_scale.dart';
import 'package:phi/domain/midi/scale_tuning.dart';
import 'package:phi/domain/midi/spawn_axis.dart';
import 'package:phi/domain/midi/spawn_source.dart';
import 'package:phi/domain/midi/transforms/agent_spawn_transform.dart';
import 'package:phi/domain/midi/transforms/scale_conformance_transform.dart';
import 'package:phi/domain/midi/transforms/spectral_mapping_transform.dart';
import 'package:phi/domain/midi/transforms/split_voice.dart';
import 'package:phi/domain/midi/transforms/splitting_transform.dart';
import 'package:phi/domain/midi/transforms/voice_routing_rule.dart';
import 'package:phi/domain/midi/transforms/voice_routing_transform.dart';
import 'package:vector_math/vector_math_64.dart';

/// The data-mutation seam (issue #95): the five table/rule-list transforms
/// carry their data field through `copyWith`, so the typed editors can replace
/// the table / rules / voices / axes / tuning in place while the chip's toggle
/// and name survive untouched.
void main() {
  test('spectral: copyWith swaps the table, keeps active + label', () {
    const t = SpectralMappingTransform(
      table: {60: 60},
      label: 'map',
      active: false,
    );
    final edited = t.copyWith(table: {60: 72.0});

    expect(edited.table, {60: 72.0});
    expect(edited.label, 'map');
    expect(edited.active, isFalse);
    // Untouched fields fall through to the original.
    expect(t.copyWith(label: 'x').table, {60: 60});
  });

  test('routing: copyWith swaps the rule list', () {
    const t = VoiceRoutingTransform(rules: [], label: 'route');
    final edited = t.copyWith(
      rules: const [PitchRangeRule(minPitch: 0, maxPitch: 127, channel: 3)],
    );

    expect(edited.rules, hasLength(1));
    expect((edited.rules.single as PitchRangeRule).channel, 3);
    expect(edited.label, 'route');
    expect(t.copyWith(active: false).rules, isEmpty);
  });

  test('split: copyWith swaps the voice list', () {
    const t = SplittingTransform(voices: [SplitVoice()], label: 'split');
    final edited = t.copyWith(
      voices: const [SplitVoice(), SplitVoice(pitchOffset: 12)],
    );

    expect(edited.voices, hasLength(2));
    expect(edited.voices.last.pitchOffset, 12);
    expect(edited.label, 'split');
    expect(t.copyWith(label: 'y').voices, hasLength(1));
  });

  test('agent spawn: copyWith rebinds axes and drift', () {
    final t = AgentSpawnTransform(
      x: SpawnAxis.of(SpawnSource.pitch),
      y: SpawnAxis.of(SpawnSource.velocity),
      z: SpawnAxis.of(SpawnSource.time),
      label: 'spawn',
    );
    final edited = t.copyWith(
      x: SpawnAxis.of(SpawnSource.channel),
      velocity: Vector3(0, 0, 1),
    );

    expect(edited.x.source, SpawnSource.channel);
    // Untouched axes fall through.
    expect(edited.y.source, SpawnSource.velocity);
    expect(edited.z.source, SpawnSource.time);
    expect(edited.velocity, Vector3(0, 0, 1));
    expect(edited.label, 'spawn');
  });

  test('scale: copyWith swaps the tuning and the tonic independently', () {
    final t = ScaleConformanceTransform.diatonic(
      scale: MusicScale.ionian,
      tonic: 60,
      label: 'scale',
    );

    final retuned = t.copyWith(tuning: ScaleTuning.justMajor);
    expect(retuned.tuning.degreesCents, ScaleTuning.justMajor.degreesCents);
    expect(retuned.tonic, 60); // tonic untouched

    final moved = t.copyWith(tonic: 62);
    expect(moved.tonic, 62);
    expect(
      moved.tuning.degreesCents,
      t.tuning.degreesCents,
    ); // tuning untouched
    expect(moved.label, 'scale');
  });
}
