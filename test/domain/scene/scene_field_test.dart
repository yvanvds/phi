import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/scene/box_volume.dart';
import 'package:phi/domain/scene/pick_ray.dart';
import 'package:phi/domain/scene/scatter.dart';
import 'package:phi/domain/scene/scene_agent.dart';
import 'package:phi/domain/scene/scene_field.dart';
import 'package:phi/domain/scene/sphere_volume.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  group('SceneField', () {
    test('starts empty', () {
      final field = SceneField();
      expect(field.isEmpty, isTrue);
      expect(field.length, 0);
      expect(field.agents, isEmpty);
    });

    test('spawn adds an agent under its key', () {
      final field = SceneField();
      field.spawn(7, SceneAgent(position: Vector3(1, 2, 3), voiceIndex: 2));

      expect(field.isEmpty, isFalse);
      expect(field.length, 1);
      expect(field.agents.single.position, Vector3(1, 2, 3));
      expect(field.agents.single.voiceIndex, 2);
    });

    test('spawn under an existing key replaces, never leaks', () {
      final field = SceneField();
      field.spawn(1, SceneAgent(position: Vector3.zero()));
      field.spawn(1, SceneAgent(position: Vector3(9, 9, 9)));

      expect(field.length, 1);
      expect(field.agents.single.position, Vector3(9, 9, 9));
    });

    test('positionOf returns a clone of the keyed agent, null when absent', () {
      final field = SceneField();
      field.spawn(4, SceneAgent(position: Vector3(1, 2, 3)));

      expect(field.positionOf(4), Vector3(1, 2, 3));
      expect(field.positionOf(999), isNull);

      // The returned vector is detached — mutating it can't perturb the field.
      field.positionOf(4)!.setValues(9, 9, 9);
      expect(field.positionOf(4), Vector3(1, 2, 3));
    });

    test('despawn removes exactly the keyed agent and reports it', () {
      final field = SceneField();
      field.spawn(1, SceneAgent(position: Vector3.zero()));
      field.spawn(2, SceneAgent(position: Vector3(5, 0, 0)));

      expect(field.despawn(1), isTrue);
      expect(field.length, 1);
      expect(field.agents.single.position, Vector3(5, 0, 0));

      // A key that was never spawned (or already gone) is a no-op false.
      expect(field.despawn(1), isFalse);
      expect(field.despawn(99), isFalse);
    });

    test('clear drops every agent', () {
      final field = SceneField();
      field.spawn(1, SceneAgent(position: Vector3.zero()));
      field.spawn(2, SceneAgent(position: Vector3.zero()));

      field.clear();
      expect(field.isEmpty, isTrue);
      expect(field.agents, isEmpty);
    });

    test('step integrates position += velocity·dt', () {
      final field = SceneField();
      field.spawn(
        1,
        SceneAgent(position: Vector3(0, 0, 0), velocity: Vector3(2, -1, 0.5)),
      );

      field.step(0.5);
      final moved = field.agents.single;
      expect(moved.position.x, closeTo(1.0, 1e-12));
      expect(moved.position.y, closeTo(-0.5, 1e-12));
      expect(moved.position.z, closeTo(0.25, 1e-12));
      // Velocity is unchanged by the baseline step (no forces yet).
      expect(moved.velocity, Vector3(2, -1, 0.5));
    });

    test('step accumulates deterministically across ticks', () {
      final field = SceneField();
      field.spawn(
        1,
        SceneAgent(position: Vector3.zero(), velocity: Vector3(1, 0, 0)),
      );

      // Ten 0.1 s ticks == one second of drift at unit speed.
      for (var i = 0; i < 10; i++) {
        field.step(0.1);
      }
      expect(field.agents.single.position.x, closeTo(1.0, 1e-9));
    });

    test('step advances every agent independently', () {
      final field = SceneField();
      field.spawn(
        1,
        SceneAgent(position: Vector3.zero(), velocity: Vector3(1, 0, 0)),
      );
      field.spawn(
        2,
        SceneAgent(position: Vector3(0, 10, 0), velocity: Vector3(0, 0, -2)),
      );

      field.step(1.0);
      final byVoice = {for (final a in field.agents) a.position.y: a};
      expect(byVoice[0.0]!.position.x, closeTo(1.0, 1e-12));
      expect(byVoice[10.0]!.position.z, closeTo(-2.0, 1e-12));
    });

    test('a zero-velocity agent stays put', () {
      final field = SceneField();
      field.spawn(1, SceneAgent(position: Vector3(3, 4, 5)));

      field.step(1.0);
      expect(field.agents.single.position, Vector3(3, 4, 5));
    });

    test('a non-positive dt never nudges the field', () {
      final field = SceneField();
      field.spawn(
        1,
        SceneAgent(position: Vector3(1, 1, 1), velocity: Vector3(9, 9, 9)),
      );

      field.step(0);
      field.step(-0.5);
      expect(field.agents.single.position, Vector3(1, 1, 1));
    });

    test('agents snapshot is detached from internal state', () {
      final field = SceneField();
      field.spawn(1, SceneAgent(position: Vector3.zero()));

      final snapshot = field.agents;
      field.spawn(2, SceneAgent(position: Vector3(1, 0, 0)));
      // The earlier snapshot did not grow when a new agent was spawned.
      expect(snapshot, hasLength(1));
    });
  });

  group('SceneField scatter', () {
    test('scatter disperses the live agents', () {
      final field = SceneField();
      field.spawn(1, SceneAgent(position: Vector3.zero()));
      field.spawn(2, SceneAgent(position: Vector3.zero()));

      field.scatter(const Scatter(positionBound: 2, seed: 42));

      // Both agents were kicked off the origin they shared.
      for (final agent in field.agents) {
        expect(agent.position, isNot(Vector3.zero()));
        expect(agent.position.x.abs(), lessThanOrEqualTo(2 + 1e-9));
        expect(agent.position.y.abs(), lessThanOrEqualTo(2 + 1e-9));
        expect(agent.position.z.abs(), lessThanOrEqualTo(2 + 1e-9));
      }
    });

    test('the same scatter over the same field state is reproducible', () {
      SceneField seeded() {
        final field = SceneField();
        field.spawn(1, SceneAgent(position: Vector3(1, 0, 0)));
        field.spawn(2, SceneAgent(position: Vector3(0, 1, 0)));
        return field;
      }

      final a = seeded()..scatter(const Scatter(positionBound: 1, seed: 7));
      final b = seeded()..scatter(const Scatter(positionBound: 1, seed: 7));

      final byA = {for (final agent in a.agents) agent.position.y: agent};
      final byB = {for (final agent in b.agents) agent.position.y: agent};
      // Keyed spawns iterate in insertion order, so the same seed lands the
      // same kick on the same agent in both fields.
      expect(a.agents[0].position, b.agents[0].position);
      expect(a.agents[1].position, b.agents[1].position);
      expect(byA.keys.toSet(), byB.keys.toSet());
    });

    test('scatter preserves keys, so despawn still finds the agent', () {
      final field = SceneField();
      field.spawn(5, SceneAgent(position: Vector3.zero()));

      field.scatter(const Scatter(positionBound: 1, seed: 1));
      expect(field.length, 1);
      expect(field.despawn(5), isTrue);
      expect(field.isEmpty, isTrue);
    });

    test('a velocity-bound scatter leaves the agents drifting apart', () {
      final field = SceneField();
      field.spawn(1, SceneAgent(position: Vector3.zero()));

      field.scatter(const Scatter(positionBound: 0, velocityBound: 1, seed: 3));
      // A pure velocity kick leaves the position put but the velocity non-zero,
      // so the next step drifts the agent.
      expect(field.agents.single.position, Vector3.zero());
      expect(field.agents.single.velocity, isNot(Vector3.zero()));

      field.step(1.0);
      expect(field.agents.single.position, isNot(Vector3.zero()));
    });

    test('scatter on an empty field is a no-op', () {
      final field = SceneField();
      field.scatter(const Scatter(positionBound: 5, seed: 1));
      expect(field.isEmpty, isTrue);
    });
  });

  group('SceneField grab', () {
    test('a fresh field is not grabbing anything', () {
      final field = SceneField();
      expect(field.isGrabbing, isFalse);
      expect(field.grabbedKey, isNull);
    });

    test('grab reports whether an agent was under the key', () {
      final field = SceneField();
      field.spawn(1, SceneAgent(position: Vector3.zero()));

      expect(field.grab(1), isTrue);
      expect(field.isGrabbing, isTrue);
      expect(field.grabbedKey, 1);

      // A key holding nothing leaves the grab untouched.
      final other = SceneField();
      expect(other.grab(99), isFalse);
      expect(other.isGrabbing, isFalse);
    });

    test('a held agent left at its own position does not move', () {
      final field = SceneField();
      field.spawn(1, SceneAgent(position: Vector3(2, 0, 0)));

      // Grab seeds the target to the current position, so with no moveGrabTo
      // the pull has zero distance to cover.
      field.grab(1);
      field.step(0.1);
      expect(field.agents.single.position, Vector3(2, 0, 0));
      expect(field.agents.single.velocity, Vector3.zero());
    });

    test('a held agent is pulled toward the grab target', () {
      final field = SceneField(grabStrength: 0.5);
      field.spawn(1, SceneAgent(position: Vector3.zero()));

      field.grab(1);
      field.moveGrabTo(Vector3(4, 0, 0));
      field.step(0.1);

      // Moves half (grabStrength) of the remaining distance this step: 0 → 2.
      expect(field.agents.single.position.x, closeTo(2.0, 1e-12));
      // Velocity is that displacement over dt (2 units in 0.1 s = 20 u/s).
      expect(field.agents.single.velocity.x, closeTo(20.0, 1e-9));
    });

    test('a rigid grab (strength 1) snaps straight onto the target', () {
      final field = SceneField(grabStrength: 1);
      field.spawn(1, SceneAgent(position: Vector3.zero()));

      field.grab(1);
      field.moveGrabTo(Vector3(3, -2, 1));
      field.step(0.25);

      expect(field.agents.single.position, Vector3(3, -2, 1));
    });

    test('a held grab converges on the target over repeated steps', () {
      final field = SceneField(grabStrength: 0.5);
      field.spawn(1, SceneAgent(position: Vector3.zero()));

      field.grab(1);
      field.moveGrabTo(Vector3(10, 0, 0));
      for (var i = 0; i < 40; i++) {
        field.step(0.1);
      }
      expect(field.agents.single.position.x, closeTo(10.0, 1e-6));
    });

    test('releasing a moving grab throws the agent with its velocity', () {
      final field = SceneField(grabStrength: 1);
      field.spawn(1, SceneAgent(position: Vector3.zero()));

      // Rigid grab dragged one unit in 0.1 s → carries 10 u/s at release.
      field.grab(1);
      field.moveGrabTo(Vector3(1, 0, 0));
      field.step(0.1);
      expect(field.agents.single.velocity.x, closeTo(10.0, 1e-9));

      field.release();
      expect(field.isGrabbing, isFalse);

      // Freed, the agent keeps drifting at the thrown velocity.
      field.step(0.1);
      expect(field.agents.single.position.x, closeTo(2.0, 1e-9));
    });

    test('releasing a settled grab lets the agent come to rest', () {
      final field = SceneField(grabStrength: 0.5);
      field.spawn(1, SceneAgent(position: Vector3.zero()));

      field.grab(1);
      field.moveGrabTo(Vector3(5, 0, 0));
      for (var i = 0; i < 60; i++) {
        field.step(0.1); // settle onto the target — velocity decays to ~0
      }
      field.release();

      final resting = field.agents.single.position.clone();
      field.step(0.1);
      // No meaningful throw: the agent barely moves after release.
      expect((field.agents.single.position - resting).length, lessThan(1e-3));
    });

    test('moveGrabTo without a grab never perturbs the field', () {
      final field = SceneField();
      field.spawn(1, SceneAgent(position: Vector3(1, 1, 1)));

      field.moveGrabTo(Vector3(9, 9, 9));
      field.step(0.1);
      expect(field.agents.single.position, Vector3(1, 1, 1));
    });

    test('the grab target is detached from the caller vector', () {
      final field = SceneField(grabStrength: 1);
      field.spawn(1, SceneAgent(position: Vector3.zero()));

      final target = Vector3(4, 0, 0);
      field.grab(1);
      field.moveGrabTo(target);
      target.setValues(0, 0, 0); // mutate after handing it over
      field.step(0.1);

      // The field kept its own copy of (4,0,0), not the now-zeroed vector.
      expect(field.agents.single.position, Vector3(4, 0, 0));
    });

    test(
      'only the grabbed agent feels the pull; others integrate normally',
      () {
        final field = SceneField(grabStrength: 1);
        field.spawn(1, SceneAgent(position: Vector3.zero()));
        field.spawn(
          2,
          SceneAgent(position: Vector3(0, 5, 0), velocity: Vector3(1, 0, 0)),
        );

        field.grab(1);
        field.moveGrabTo(Vector3(9, 0, 0));
        field.step(1.0);

        final byKey = {for (final a in field.agents) a.position.y: a};
        expect(byKey[0.0]!.position.x, closeTo(9.0, 1e-9)); // grabbed → snapped
        expect(byKey[5.0]!.position.x, closeTo(1.0, 1e-9)); // free → drifted
      },
    );

    test('despawning the grabbed agent releases the grab', () {
      final field = SceneField();
      field.spawn(1, SceneAgent(position: Vector3.zero()));
      field.grab(1);

      expect(field.despawn(1), isTrue);
      expect(field.isGrabbing, isFalse);
      expect(field.grabbedKey, isNull);
    });

    test('despawning a different agent leaves the grab intact', () {
      final field = SceneField();
      field.spawn(1, SceneAgent(position: Vector3.zero()));
      field.spawn(2, SceneAgent(position: Vector3(5, 0, 0)));
      field.grab(1);

      field.despawn(2);
      expect(field.isGrabbing, isTrue);
      expect(field.grabbedKey, 1);
    });

    test('clear releases any active grab', () {
      final field = SceneField();
      field.spawn(1, SceneAgent(position: Vector3.zero()));
      field.grab(1);

      field.clear();
      expect(field.isGrabbing, isFalse);
    });

    test('grabbing a new key replaces the previous grab', () {
      final field = SceneField(grabStrength: 1);
      field.spawn(1, SceneAgent(position: Vector3(0, 1, 0)));
      field.spawn(2, SceneAgent(position: Vector3(0, 2, 0)));

      field.grab(1);
      field.grab(2); // regrab re-seeds the target onto agent 2's position
      expect(field.grabbedKey, 2);

      field.moveGrabTo(Vector3(9, 2, 0));
      field.step(0.1);

      final byRow = {for (final a in field.agents) a.position.y: a};
      // Only the now-grabbed agent 2 is pulled; agent 1 is left where it was.
      expect(byRow[2.0]!.position.x, closeTo(9.0, 1e-9));
      expect(byRow[1.0]!.position.x, closeTo(0.0, 1e-9));
    });

    test('an out-of-range grabStrength is rejected', () {
      expect(() => SceneField(grabStrength: 0), throwsA(isA<AssertionError>()));
      expect(
        () => SceneField(grabStrength: 1.5),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('SceneField pick', () {
    PickRay downX({Vector3? from}) =>
        PickRay(origin: from ?? Vector3.zero(), direction: Vector3(1, 0, 0));

    test('picks the agent under the ray', () {
      final field = SceneField();
      field.spawn(1, SceneAgent(position: Vector3(10, 0, 0)));

      expect(field.pick(downX()), 1);
    });

    test('returns null when the ray hits no agent', () {
      final field = SceneField();
      field.spawn(1, SceneAgent(position: Vector3(10, 5, 0)));

      expect(field.pick(downX()), isNull);
    });

    test('picks the nearest of several agents along the ray', () {
      final field = SceneField();
      field.spawn(1, SceneAgent(position: Vector3(20, 0, 0)));
      field.spawn(2, SceneAgent(position: Vector3(5, 0, 0)));
      field.spawn(3, SceneAgent(position: Vector3(12, 0, 0)));

      // All three sit on the +X axis; the closest to the origin wins.
      expect(field.pick(downX()), 2);
    });

    test('a wider pick radius can catch an agent a tight one misses', () {
      final field = SceneField();
      // 0.5 off-axis: outside the default 0.55 halo only barely — use a clear
      // gap so intent is unambiguous.
      field.spawn(1, SceneAgent(position: Vector3(10, 1, 0)));

      expect(field.pick(downX()), isNull); // default 0.55 radius misses
      expect(field.pick(downX(), radius: 2), 1); // a 2-unit radius catches it
    });

    test('picking an empty field is null', () {
      final field = SceneField();
      expect(field.pick(downX()), isNull);
    });
  });

  group('SceneField effect volumes', () {
    SphereVolume reverbAtOrigin({double radius = 1, double send = 0.5}) =>
        SphereVolume(
          center: Vector3.zero(),
          radius: radius,
          effect: 'reverb',
          send: send,
        );

    test('a step routes an agent inside a volume through its send', () {
      final field = SceneField();
      field.addVolume(reverbAtOrigin(send: 0.5));
      field.spawn(1, SceneAgent(position: Vector3(0.5, 0, 0)));

      field.step(0.1);
      expect(field.agents.single.sends, {'reverb': 0.5});
    });

    test('an agent outside every volume carries no sends', () {
      final field = SceneField();
      field.addVolume(reverbAtOrigin());
      field.spawn(1, SceneAgent(position: Vector3(5, 0, 0)));

      field.step(0.1);
      expect(field.agents.single.sends, isEmpty);
    });

    test('an agent drifting into a volume gains the send that step', () {
      final field = SceneField();
      field.addVolume(reverbAtOrigin(radius: 1, send: 0.7));
      // Starts outside (x=2), moving toward the origin at unit speed.
      field.spawn(
        1,
        SceneAgent(position: Vector3(2, 0, 0), velocity: Vector3(-1, 0, 0)),
      );

      field.step(0.5); // -> x = 1.5, still outside
      expect(field.agents.single.sends, isEmpty);

      field.step(1.0); // -> x = 0.5, now inside
      expect(field.agents.single.sends, {'reverb': 0.7});
    });

    test('an agent drifting out of a volume drops the send that step', () {
      final field = SceneField();
      field.addVolume(reverbAtOrigin(radius: 1, send: 0.7));
      field.spawn(
        1,
        SceneAgent(position: Vector3(0, 0, 0), velocity: Vector3(1, 0, 0)),
      );

      field.step(0.5); // -> x = 0.5, inside
      expect(field.agents.single.sends, {'reverb': 0.7});

      field.step(1.0); // -> x = 1.5, outside
      expect(field.agents.single.sends, isEmpty);
    });

    test('membership tracks position, not the moment of entry', () {
      // A volume added after an agent is already sitting inside still routes
      // it on the next step — sends are a pure function of position.
      final field = SceneField();
      field.spawn(1, SceneAgent(position: Vector3.zero()));

      field.step(0.1);
      expect(field.agents.single.sends, isEmpty);

      field.addVolume(reverbAtOrigin(send: 0.4));
      field.step(0.1);
      expect(field.agents.single.sends, {'reverb': 0.4});
    });

    test('overlapping volumes collect one send per effect', () {
      final field = SceneField();
      field.addVolume(reverbAtOrigin(send: 0.3));
      field.addVolume(
        BoxVolume(
          corner: Vector3(-1, -1, -1),
          opposite: Vector3(1, 1, 1),
          effect: 'delay',
          send: 0.9,
        ),
      );
      field.spawn(1, SceneAgent(position: Vector3.zero()));

      field.step(0.1);
      expect(field.agents.single.sends, {'reverb': 0.3, 'delay': 0.9});
    });

    test('overlapping volumes on the same effect keep the larger send', () {
      final field = SceneField();
      field.addVolume(reverbAtOrigin(send: 0.3));
      field.addVolume(reverbAtOrigin(send: 0.8));
      field.spawn(1, SceneAgent(position: Vector3.zero()));

      field.step(0.1);
      expect(field.agents.single.sends, {'reverb': 0.8});
    });

    test('removeVolume stops routing agents through it', () {
      final field = SceneField();
      final volume = reverbAtOrigin(send: 0.5);
      field.addVolume(volume);
      field.spawn(1, SceneAgent(position: Vector3.zero()));

      field.step(0.1);
      expect(field.agents.single.sends, {'reverb': 0.5});

      expect(field.removeVolume(volume), isTrue);
      field.step(0.1);
      expect(field.agents.single.sends, isEmpty);
      // Removing again is a no-op false.
      expect(field.removeVolume(volume), isFalse);
    });

    test('clearVolumes empties the set and clears sends on the next step', () {
      final field = SceneField();
      field.addVolume(reverbAtOrigin(send: 0.5));
      field.spawn(1, SceneAgent(position: Vector3.zero()));
      field.step(0.1);

      field.clearVolumes();
      expect(field.volumes, isEmpty);
      field.step(0.1);
      expect(field.agents.single.sends, isEmpty);
    });

    test('volumes snapshot is detached from internal state', () {
      final field = SceneField();
      field.addVolume(reverbAtOrigin());

      final snapshot = field.volumes;
      field.addVolume(reverbAtOrigin());
      expect(snapshot, hasLength(1));
    });

    test('an agent send map is an unmodifiable snapshot', () {
      final field = SceneField();
      field.addVolume(reverbAtOrigin(send: 0.5));
      field.spawn(1, SceneAgent(position: Vector3.zero()));
      field.step(0.1);

      expect(
        () => field.agents.single.sends['reverb'] = 1.0,
        throwsUnsupportedError,
      );
    });
  });
}
