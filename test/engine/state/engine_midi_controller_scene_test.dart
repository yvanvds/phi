import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/spawn_axis.dart';
import 'package:phi/domain/midi/spawn_source.dart';
import 'package:phi/domain/midi/transforms/agent_spawn_transform.dart';
import 'package:phi/domain/scene/pick_ray.dart';
import 'package:phi/domain/scene/scatter.dart';
import 'package:phi/domain/scene/sphere_volume.dart';
import 'package:phi/engine/state/engine_midi_controller.dart';
import 'package:vector_math/vector_math_64.dart';

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

AgentSpawnTransform _spawnTransform({bool active = true, Vector3? velocity}) =>
    AgentSpawnTransform(
      x: SpawnAxis.of(SpawnSource.pitch, outMin: 0, outMax: 127),
      y: SpawnAxis.of(SpawnSource.velocity, outMin: 0, outMax: 1),
      z: SpawnAxis.of(SpawnSource.time, outMin: 0, outMax: 4),
      label: 'spawn',
      active: active,
      velocity: velocity,
    );

MidiTransformChain _chainWith(AgentSpawnTransform t) =>
    MidiTransformChain(source: _clip(), transforms: [t]);

/// A one-note clip whose single note fills the whole bar, so the spawned agent
/// stays alive through a grab-and-drag. Pitch 60 → x 60, velocity 1 → y 1,
/// start 0 → z 0, so it spawns at (60, 1, 0).
MidiTransformChain _heldChain() => MidiTransformChain(
  source: MidiClip(
    name: 'held',
    bars: 1,
    notes: const [
      MidiNote(pitch: 60, start: 0.0, duration: 4.0, velocity: 1.0),
    ],
  ),
  // Zero spawn velocity — only the grab moves the agent.
  transforms: [_spawnTransform()],
);

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

    test('a spawned agent drifts each tick (position += velocity·dt)', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        // 1 scene-unit/second along +X. Note A spawns at x=60 (pitch 60).
        final controller = EngineMidiController(
          chain: _chainWith(_spawnTransform(velocity: Vector3(1, 0, 0))),
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        controller.play();

        // Note A is alive over beats [0,1) = [0s, 0.5s] @ 120 BPM. Sample twice
        // inside that window: the agent must have drifted past its spawn x and
        // keep advancing between samples.
        async.elapse(const Duration(milliseconds: 200)); // ~0.2 s of drift
        expect(renderer.lastAgents, hasLength(1));
        final xEarly = renderer.lastAgents.single.position.x;
        expect(xEarly, greaterThan(60)); // moved off its spawn point
        expect(xEarly, closeTo(60.2, 0.02)); // ~0.2 s at 1 unit/s

        async.elapse(const Duration(milliseconds: 200)); // ~0.4 s total
        final xLate = renderer.lastAgents.single.position.x;
        expect(xLate, greaterThan(xEarly)); // still advancing
        expect(xLate, closeTo(60.4, 0.02));

        controller.stop();
        controller.dispose();
      });
    });

    test('with no velocity, spawned agents stay put', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          chain: _chainWith(_spawnTransform()), // zero velocity
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 400)); // well into note A
        expect(renderer.lastAgents.single.position.x, closeTo(60, 1e-9));

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

        // Notes still reached the engine transport — the missing scene sink is
        // a silent no-op, not a crash.
        expect(gateway.transport?.events, isNotEmpty);

        controller.dispose();
      });
    });
  });

  group('EngineMidiController — scatter (issue #81)', () {
    test('scatter disperses the live agent and pushes it to the sink', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          chain: _chainWith(_spawnTransform()), // zero spawn velocity
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        controller.play();
        async.elapse(
          const Duration(milliseconds: 300),
        ); // note A alive, at x=60
        expect(renderer.lastAgents, hasLength(1));
        final before = renderer.lastAgents.single.position.clone();
        final callsBefore = renderer.calls.length;

        controller.scatter(const Scatter(positionBound: 2, seed: 42));

        // The sink received the kicked set, and the agent moved but stayed
        // within one bound of where it sat.
        expect(renderer.calls.length, greaterThan(callsBefore));
        final after = renderer.lastAgents.single.position;
        expect(after, isNot(before));
        expect((after - before).x.abs(), lessThanOrEqualTo(2 + 1e-9));
        expect((after - before).y.abs(), lessThanOrEqualTo(2 + 1e-9));
        expect((after - before).z.abs(), lessThanOrEqualTo(2 + 1e-9));

        controller.stop();
        controller.dispose();
      });
    });

    test('scatter is deterministic across two identical runs', () {
      Vector3 scatteredX() {
        return fakeAsync((async) {
          final renderer = FakeSceneRenderer();
          final controller = EngineMidiController(
            chain: _chainWith(_spawnTransform()),
            gateway: FakeMidiGateway(),
            agentSink: renderer,
          );
          controller.play();
          async.elapse(const Duration(milliseconds: 300));
          controller.scatter(const Scatter(positionBound: 2, seed: 7));
          final pos = renderer.lastAgents.single.position.clone();
          controller.stop();
          controller.dispose();
          return pos;
        });
      }

      expect(scatteredX(), scatteredX());
    });

    test('scatter with no live agents never touches the sink', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          chain: _chainWith(_spawnTransform()),
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        // Not playing — nothing spawned yet.
        controller.scatter(const Scatter(positionBound: 2, seed: 1));
        expect(renderer.calls, isEmpty);

        controller.dispose();
      });
    });
  });

  group('EngineMidiController — grab (issue #82)', () {
    // A ray straight down +Z through the held agent's spawn point (60, 1, 0).
    PickRay rayThroughSpawn() =>
        PickRay(origin: Vector3(60, 1, -10), direction: Vector3(0, 0, 1));

    test('pick + grab + drag pulls the live agent toward the target', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          chain: _heldChain(),
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        controller.play();
        async.elapse(
          const Duration(milliseconds: 300),
        ); // agent alive at (60,1,0)
        expect(renderer.lastAgents, hasLength(1));

        final key = controller.pick(rayThroughSpawn());
        expect(
          key,
          isNotNull,
          reason: 'the ray passes through the spawn point',
        );
        expect(controller.grab(key!), isTrue);

        final yBefore = renderer.lastAgents.single.position.y;
        controller.moveGrabTo(Vector3(60, 8, 0));
        async.elapse(const Duration(milliseconds: 200)); // ~12 ticks of pull

        final yAfter = renderer.lastAgents.single.position.y;
        expect(yAfter, greaterThan(yBefore)); // dragged toward y = 8
        expect(yAfter, lessThanOrEqualTo(8 + 1e-9)); // never past the target

        controller.stop();
        controller.dispose();
      });
    });

    test('releasing a moving grab keeps the agent drifting (a throw)', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          chain: _heldChain(),
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 300));
        controller.grab(controller.pick(rayThroughSpawn())!);

        // Drag toward y = 8, then let go while still in motion.
        controller.moveGrabTo(Vector3(60, 8, 0));
        async.elapse(const Duration(milliseconds: 100));
        final yAtRelease = renderer.lastAgents.single.position.y;
        controller.releaseGrab();

        async.elapse(const Duration(milliseconds: 100)); // free flight
        expect(renderer.lastAgents.single.position.y, greaterThan(yAtRelease));

        controller.stop();
        controller.dispose();
      });
    });

    test('grabbing a key with no live agent is a no-op false', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          chain: _heldChain(),
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 300));

        expect(controller.grab(999999), isFalse);

        controller.stop();
        controller.dispose();
      });
    });

    test('pick returns null when the ray misses every live agent', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          chain: _heldChain(),
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 300));

        // A ray far from the agent at (60, 1, 0).
        final key = controller.pick(
          PickRay(origin: Vector3(0, 0, -10), direction: Vector3(0, 0, 1)),
        );
        expect(key, isNull);

        controller.stop();
        controller.dispose();
      });
    });
  });

  group('EngineMidiController — pick-friendly Scene demo (issue #90)', () {
    EngineMidiController demoController(FakeSceneRenderer renderer) =>
        EngineMidiController(
          chain: _chainWith(_spawnTransform()),
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

    test('loadSceneDemo populates the field and pushes it to the sink', () {
      final renderer = FakeSceneRenderer();
      final controller = demoController(renderer);

      expect(controller.isSceneDemoLoaded, isFalse);
      controller.loadSceneDemo();

      expect(controller.isSceneDemoLoaded, isTrue);
      expect(renderer.lastAgents, isNotEmpty);
      expect(
        renderer.lastAgents.map((a) => a.voiceIndex).toSet().length,
        renderer.lastAgents.length,
        reason: 'each demo agent keeps its own voice colour',
      );

      controller.dispose();
    });

    test('demo agents are pickable and settled (well-separated)', () {
      final renderer = FakeSceneRenderer();
      final controller = demoController(renderer);
      controller.loadSceneDemo();

      // Aim a ray straight down +Z through each agent in turn: each resolves to
      // exactly one key, proving they are spread beyond the pick radius.
      final keys = <int?>{};
      for (final agent in renderer.lastAgents) {
        final p = agent.position;
        final key = controller.pick(
          PickRay(
            origin: Vector3(p.x, p.y, p.z - 10),
            direction: Vector3(0, 0, 1),
          ),
        );
        expect(key, isNotNull);
        keys.add(key);
      }
      expect(
        keys.length,
        renderer.lastAgents.length,
        reason: 'every agent picks to a unique key',
      );

      controller.dispose();
    });

    test('clearSceneDemo drops the agents and clears the sink', () {
      final renderer = FakeSceneRenderer();
      final controller = demoController(renderer);
      controller.loadSceneDemo();
      expect(renderer.lastAgents, isNotEmpty);

      controller.clearSceneDemo();
      expect(controller.isSceneDemoLoaded, isFalse);
      expect(renderer.lastAgents, isEmpty);

      // Idempotent: a second clear with nothing loaded never touches the sink.
      final callsBefore = renderer.calls.length;
      controller.clearSceneDemo();
      expect(renderer.calls.length, callsBefore);

      controller.dispose();
    });

    test('stopping the transport drops a loaded demo', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = demoController(renderer);
        controller.loadSceneDemo();

        controller.play();
        async.elapse(const Duration(milliseconds: 50));
        controller.stop();

        expect(renderer.lastAgents, isEmpty);
        expect(controller.isSceneDemoLoaded, isFalse);

        controller.dispose();
      });
    });

    test('demo keys never collide with a playback voice key', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = demoController(renderer);
        controller.loadSceneDemo();
        final demoCount = renderer.lastAgents.length;

        // Playing spawns note agents on top of the demo set — the counts add,
        // so no note-on overwrote a demo agent (a key clash would drop one).
        controller.play();
        async.elapse(const Duration(milliseconds: 300)); // note A alive
        expect(renderer.lastAgents.length, demoCount + 1);

        controller.stop();
        controller.dispose();
      });
    });
  });

  group('EngineMidiController — surface pick/step seam (issue #86)', () {
    // The held clip's single note is pitch 60 on channel 0, so its voice key is
    // 0 * 128 + 60 = 60.
    const heldKey = 60;

    test('agentPosition returns the live agent, null for an unknown key', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          chain: _heldChain(), // zero spawn velocity → stays at (60, 1, 0)
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 300));

        final pos = controller.agentPosition(heldKey);
        expect(pos, isNotNull);
        expect(pos!.x, closeTo(60, 1e-9));
        expect(pos.y, closeTo(1, 1e-9));
        expect(controller.agentPosition(999999), isNull);

        // After stop the field is cleared, so the position is gone too.
        controller.stop();
        expect(controller.agentPosition(heldKey), isNull);

        controller.dispose();
      });
    });

    test('agentPosition hands back a clone the caller cannot mutate', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          chain: _heldChain(),
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 300));

        controller.agentPosition(heldKey)!.setValues(9, 9, 9);
        // The field's own copy is untouched.
        expect(controller.agentPosition(heldKey)!.x, closeTo(60, 1e-9));

        controller.stop();
        controller.dispose();
      });
    });

    test('stepFromSurface is a no-op while playing (no double-step)', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          // Drifting agent, so a stray extra step would visibly overshoot.
          chain: _chainWith(_spawnTransform(velocity: Vector3(1, 0, 0))),
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 200)); // agent A drifting
        expect(renderer.lastAgents, hasLength(1));
        final callsBefore = renderer.calls.length;
        final xBefore = renderer.lastAgents.single.position.x;

        // A big surface step while the transport runs must change nothing —
        // the playback tick owns stepping.
        controller.stepFromSurface(1.0);
        expect(renderer.calls.length, callsBefore); // never touched the sink
        expect(renderer.lastAgents.single.position.x, xBefore);

        controller.stop();
        controller.dispose();
      });
    });

    test('stepFromSurface with an empty field never touches the sink', () {
      final renderer = FakeSceneRenderer();
      final controller = EngineMidiController(
        chain: _chainWith(_spawnTransform()),
        gateway: FakeMidiGateway(),
        agentSink: renderer,
      );

      // Not playing, nothing spawned.
      controller.stepFromSurface(0.1);
      expect(renderer.calls, isEmpty);

      controller.dispose();
    });
  });

  group('EngineMidiController — effect volumes (issue #93, epic #68)', () {
    // A sphere around note A's spawn point (60, 1, 0), radius 1 — so the
    // zero-velocity spawned agent sits inside it.
    SphereVolume aroundSpawn({String effect = 'reverb', double send = 0.7}) =>
        SphereVolume(
          center: Vector3(60, 1, 0),
          radius: 1,
          effect: effect,
          send: send,
        );

    test('a spawned agent inside a placed volume gains its send', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          chain: _chainWith(
            _spawnTransform(),
          ), // zero velocity → stays at spawn
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        controller.addEffectVolume(aroundSpawn());
        controller.play();
        async.elapse(
          const Duration(milliseconds: 300),
        ); // note A alive + stepped

        expect(renderer.lastAgents, hasLength(1));
        expect(renderer.lastAgents.single.sends, {'reverb': 0.7});

        controller.stop();
        controller.dispose();
      });
    });

    test('a spawned agent outside every volume carries no sends', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          chain: _chainWith(_spawnTransform()),
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        // A volume far from the agent at (60, 1, 0).
        controller.addEffectVolume(
          SphereVolume(
            center: Vector3(0, 0, 0),
            radius: 1,
            effect: 'reverb',
            send: 0.7,
          ),
        );
        controller.play();
        async.elapse(const Duration(milliseconds: 300));

        expect(renderer.lastAgents.single.sends, isEmpty);

        controller.stop();
        controller.dispose();
      });
    });

    test('a drifting agent gains the send as it crosses into a volume', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        // Drift +X at 1 unit/s from the spawn x=60. Place a volume it reaches
        // only after ~0.3 s of drift, so it starts outside and crosses in.
        final controller = EngineMidiController(
          chain: _chainWith(_spawnTransform(velocity: Vector3(1, 0, 0))),
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );
        controller.addEffectVolume(
          SphereVolume(
            center: Vector3(60.4, 1, 0),
            radius: 0.15,
            effect: 'delay',
            send: 0.5,
          ),
        );

        controller.play();
        async.elapse(
          const Duration(milliseconds: 100),
        ); // ~x=60.1, still outside
        expect(renderer.lastAgents.single.sends, isEmpty);

        async.elapse(const Duration(milliseconds: 300)); // ~x=60.4, now inside
        expect(renderer.lastAgents.single.sends, {'delay': 0.5});

        controller.stop();
        controller.dispose();
      });
    });

    test('removing the volume drops the send on the next step', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          chain: _chainWith(_spawnTransform()),
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        final volume = aroundSpawn();
        controller.addEffectVolume(volume);
        controller.play();
        async.elapse(const Duration(milliseconds: 300));
        expect(renderer.lastAgents.single.sends, {'reverb': 0.7});

        expect(controller.removeEffectVolume(volume), isTrue);
        async.elapse(const Duration(milliseconds: 50)); // one more step
        expect(renderer.lastAgents.single.sends, isEmpty);

        controller.stop();
        controller.dispose();
      });
    });

    test('clearEffectVolumes drops sends and empties the snapshot', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          chain: _chainWith(_spawnTransform()),
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        controller.addEffectVolume(aroundSpawn());
        controller.addEffectVolume(aroundSpawn(effect: 'delay', send: 0.3));
        expect(controller.effectVolumes, hasLength(2));

        controller.play();
        async.elapse(const Duration(milliseconds: 300));
        expect(renderer.lastAgents.single.sends, hasLength(2));

        controller.clearEffectVolumes();
        expect(controller.effectVolumes, isEmpty);
        async.elapse(const Duration(milliseconds: 50));
        expect(renderer.lastAgents.single.sends, isEmpty);

        controller.stop();
        controller.dispose();
      });
    });

    test('placed volumes outlive a transport stop', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          chain: _chainWith(_spawnTransform()),
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        controller.addEffectVolume(aroundSpawn());
        controller.play();
        async.elapse(const Duration(milliseconds: 300));
        expect(renderer.lastAgents.single.sends, {'reverb': 0.7});

        controller.stop(); // clears agents, but the volume stays placed
        expect(controller.effectVolumes, hasLength(1));

        // A fresh run: the respawned agent picks the send back up.
        controller.play();
        async.elapse(const Duration(milliseconds: 300));
        expect(renderer.lastAgents.single.sends, {'reverb': 0.7});

        controller.stop();
        controller.dispose();
      });
    });

    test('effectVolumes returns a detached snapshot', () {
      final controller = EngineMidiController(
        chain: _chainWith(_spawnTransform()),
        gateway: FakeMidiGateway(),
      );

      controller.addEffectVolume(aroundSpawn());
      final snapshot = controller.effectVolumes;
      controller.addEffectVolume(aroundSpawn(effect: 'delay', send: 0.3));

      // The earlier snapshot didn't grow when a second volume was added.
      expect(snapshot, hasLength(1));
      expect(controller.effectVolumes, hasLength(2));

      controller.dispose();
    });
  });
}
