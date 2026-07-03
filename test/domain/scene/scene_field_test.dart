import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/scene/scene_agent.dart';
import 'package:phi/domain/scene/scene_field.dart';
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
}
