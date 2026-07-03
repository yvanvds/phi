import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/scene/scene_agent.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  group('SceneAgent', () {
    test('velocity defaults to zero', () {
      final agent = SceneAgent(position: Vector3(1, 2, 3));
      expect(agent.velocity, Vector3.zero());
      expect(agent.voiceIndex, 0);
    });

    test('carries an explicit velocity and voice', () {
      final agent = SceneAgent(
        position: Vector3.zero(),
        velocity: Vector3(0, 0.2, 0),
        voiceIndex: 4,
      );
      expect(agent.velocity, Vector3(0, 0.2, 0));
      expect(agent.voiceIndex, 4);
    });

    test('copyWith replaces only the given fields', () {
      final agent = SceneAgent(
        position: Vector3(1, 0, 0),
        velocity: Vector3(0, 1, 0),
        voiceIndex: 2,
      );

      final moved = agent.copyWith(position: Vector3(2, 0, 0));
      expect(moved.position, Vector3(2, 0, 0));
      expect(moved.velocity, Vector3(0, 1, 0));
      expect(moved.voiceIndex, 2);
    });

    test(
      'copyWith clones vectors so the source cannot be mutated through it',
      () {
        final agent = SceneAgent(
          position: Vector3(1, 0, 0),
          velocity: Vector3(0, 1, 0),
        );
        final clone = agent.copyWith();

        clone.position.x = 99;
        clone.velocity.y = 99;
        expect(agent.position, Vector3(1, 0, 0));
        expect(agent.velocity, Vector3(0, 1, 0));
      },
    );
  });
}
