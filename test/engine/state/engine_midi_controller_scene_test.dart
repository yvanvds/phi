import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/spawn_axis.dart';
import 'package:phi/domain/midi/spawn_source.dart';
import 'package:phi/domain/midi/transforms/agent_spawn_transform.dart';
import 'package:phi/engine/state/engine_midi_controller.dart';

import '../test_doubles/fake_midi_gateway.dart';
import '../test_doubles/fake_scene_renderer.dart';

/// A one-bar clip (4 beats) with two well-separated notes. Note A: beat 0,
/// duration 1. Note B: beat 2, duration 1. Non-overlapping so each spawn and
/// despawn is unambiguous.
MidiClip _clip() => MidiClip(
  name: 'spawns',
  bars: 1,
  notes: const [
    MidiNote(pitch: 60, start: 0.0, duration: 1.0, velocity: 1.0),
    MidiNote(pitch: 72, start: 2.0, duration: 1.0, velocity: 0.5, channel: 3),
  ],
);

AgentSpawnTransform _spawnTransform({bool active = true}) =>
    AgentSpawnTransform(
      x: SpawnAxis.of(SpawnSource.pitch, outMin: 0, outMax: 127),
      y: SpawnAxis.of(SpawnSource.velocity, outMin: 0, outMax: 1),
      z: SpawnAxis.of(SpawnSource.time, outMin: 0, outMax: 4),
      label: 'spawn',
      active: active,
    );

MidiTransformChain _chainWith(AgentSpawnTransform t) =>
    MidiTransformChain(source: _clip(), transforms: [t]);

void main() {
  group('EngineMidiController — scene agent spawns (issue #37)', () {
    test('a note-on spawns an agent; its note-off despawns it', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          chain: _chainWith(_spawnTransform()),
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        controller.play();

        // 0.3 s @ 120 BPM = 0.6 beat — past note A's onset (beat 0) but before
        // its note-off (beat 1). One agent alive.
        async.elapse(const Duration(milliseconds: 300));
        expect(renderer.lastAgents, hasLength(1));
        // pitch 60 → x 60, velocity 1 → y 1, start 0 → z 0.
        expect(renderer.lastAgents.single.position.x, closeTo(60, 1e-9));
        expect(renderer.lastAgents.single.position.y, closeTo(1, 1e-9));
        expect(renderer.lastAgents.single.voiceIndex, 0);

        // Cross note A's note-off (beat 1 = 0.5 s) — the scene empties again.
        async.elapse(const Duration(milliseconds: 400)); // now ~1.4 beats
        expect(renderer.lastAgents, isEmpty);

        // Note B (beat 2, channel 3) spawns with its own voice + position.
        async.elapse(const Duration(milliseconds: 400)); // now ~2.2 beats
        expect(renderer.lastAgents, hasLength(1));
        expect(renderer.lastAgents.single.voiceIndex, 3);
        expect(renderer.lastAgents.single.position.x, closeTo(72, 1e-9));

        controller.stop();
        controller.dispose();
      });
    });

    test('stop clears every live agent', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          chain: _chainWith(_spawnTransform()),
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 300)); // agent A alive
        expect(renderer.lastAgents, hasLength(1));

        controller.stop();
        expect(renderer.lastAgents, isEmpty);

        controller.dispose();
      });
    });

    test('an inactive spawn transform never touches the sink', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          chain: _chainWith(_spawnTransform(active: false)),
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 900)); // past both notes
        controller.stop();

        // No spawn transform contributed, so setAgents was never called.
        expect(renderer.calls.where((c) => c.startsWith('setAgents')), isEmpty);

        controller.dispose();
      });
    });

    test('with no sink wired, playback still runs (spawns no-op)', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _chainWith(_spawnTransform()),
          gateway: gateway,
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 300));
        controller.stop();

        // Notes still fired through the MIDI gateway — the missing scene sink
        // is a silent no-op, not a crash.
        expect(gateway.calls.any((c) => c.startsWith('noteOn')), isTrue);

        controller.dispose();
      });
    });
  });
}
