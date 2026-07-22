import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/runtime/runtime_variable_registry.dart';
import 'package:phi/domain/state_machine/slices/clip_slice_entry.dart';
import 'package:phi/domain/state_machine/slices/mix_slice_entry.dart';
import 'package:phi/domain/state_machine/slices/tempo_slice_entry.dart';
import 'package:phi/domain/time_domains/time_domain.dart';
import 'package:phi/engine/state/engine_state_slice_source.dart';
import 'package:phi/engine/state/mix_tree_node.dart';
import 'package:phi/engine/state/mixer_channel.dart';

/// The production capture-from-live source (issue #242): each category reads
/// its owning controller's current state — playing clips through the MIDI
/// manager's entries, buses off the materialised mix tree, values off the
/// runtime-variable registry, tempos off the bound registry's `domain.`
/// entities.
void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  late List<ClipSliceEntry> playing;
  late List<MixTreeNode> tree;
  late RuntimeVariableRegistry variables;
  late ProjectRegistry registry;
  late EngineStateSliceSource source;

  setUp(() {
    playing = [];
    tree = [];
    variables = RuntimeVariableRegistry();
    registry = ProjectRegistry();
    source = EngineStateSliceSource(
      playingClips: () => playing,
      mixNodes: () => tree,
      variables: () => variables,
      registry: () => registry,
    );
  });

  tearDown(() {
    variables.dispose();
    registry.dispose();
  });

  test('clips read the playing entries at call time', () {
    expect(source.captureClips(), isEmpty);
    playing = [ClipSliceEntry(clip: addr('clip.drums'), loop: false)];
    expect(source.captureClips(), playing);
  });

  test('mix walks strips and group buses with their live volume/mute', () {
    final pads = MixerChannel.user(id: 1, name: 'pads', voice: 2)
      ..applyVolume(0.4)
      ..applyMuted(true);
    final lead = MixerChannel.user(id: 2, name: 'lead', voice: 3)
      ..applyVolume(0.9);
    final bus = MixerChannel.user(id: 3, name: 'synths', voice: 1)
      ..applyVolume(0.7);
    tree = [
      MixTreeNode(
        channel: bus,
        address: addr('mix.synths'),
        isGroup: true,
        children: [
          MixTreeNode(
            channel: pads,
            address: addr('mix.synths.pads'),
            isGroup: false,
          ),
        ],
      ),
      MixTreeNode(channel: lead, address: addr('mix.lead'), isGroup: false),
    ];

    expect(source.captureMix(), [
      MixSliceEntry(bus: addr('mix.synths'), volume: 0.7),
      MixSliceEntry(bus: addr('mix.synths.pads'), volume: 0.4, muted: true),
      MixSliceEntry(bus: addr('mix.lead'), volume: 0.9),
    ]);
  });

  test('variables snapshot the registry current values', () {
    expect(source.captureVariables(), isEmpty);
    variables.define(name: 'section', values: ['a', 'b'], current: 'b');
    variables.define(name: 'mode', values: ['lead']);
    expect(source.captureVariables(), {'section': 'b', 'mode': 'lead'});

    // Capture reads the value at call time, not at wiring time.
    variables.setValue('section', 'a');
    expect(source.captureVariables()['section'], 'a');
  });

  test('tempos read the top-level domain. entities with typed payloads', () {
    registry.createEntity(
      addr('domain.drum'),
      payload: const TimeDomain(name: 'drum', tempo: 124),
    );
    registry.createEntity(
      addr('domain.pad'),
      payload: const TimeDomain(name: 'pad', tempo: 96),
    );
    // A payload the codec has not typed is skipped — the same tolerance the
    // engine's session-domain materialisation applies.
    registry.createEntity(
      addr('domain.raw'),
      payload: const {'name': 'raw', 'tempo': 80},
    );

    expect(source.captureTempos(), [
      TempoSliceEntry(domain: addr('domain.drum'), bpm: 124),
      TempoSliceEntry(domain: addr('domain.pad'), bpm: 96),
    ]);
  });
}
