import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/scene/box_volume.dart';
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
