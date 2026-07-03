import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/scene/scatter.dart';
import 'package:phi/domain/scene/scene_agent.dart';
import 'package:vector_math/vector_math_64.dart';

SceneAgent _agent({Vector3? position, Vector3? velocity, int voiceIndex = 0}) =>
    SceneAgent(
      position: position ?? Vector3.zero(),
      velocity: velocity,
      voiceIndex: voiceIndex,
    );

/// A cluster of identical agents at the origin — a worst-case scatter input,
/// since any dispersal has to come purely from the impulse.
List<SceneAgent> _cluster(int n) =>
    List.generate(n, (_) => _agent(position: Vector3.zero()));

void main() {
  group('Scatter', () {
    test('same seed and set produce identical dispersal (reproducible)', () {
      const scatter = Scatter(positionBound: 2, velocityBound: 1, seed: 42);
      final input = _cluster(5);

      final a = scatter.apply(input);
      final b = scatter.apply(input);
      for (var i = 0; i < input.length; i++) {
        expect(a[i].position, b[i].position);
        expect(a[i].velocity, b[i].velocity);
      }
    });

    test('a different seed generally produces a different throw', () {
      final input = _cluster(5);
      final a = const Scatter(positionBound: 2, seed: 1).apply(input);
      final b = const Scatter(positionBound: 2, seed: 2).apply(input);

      final differ = [
        for (var i = 0; i < input.length; i++)
          if (a[i].position != b[i].position) i,
      ];
      expect(differ, isNotEmpty);
    });

    test('position kicks stay within the configured bound (per axis)', () {
      const bound = 1.5;
      const scatter = Scatter(positionBound: bound, seed: 7);
      final input = _cluster(200);

      final out = scatter.apply(input);
      for (final a in out) {
        // Input sits at the origin, so the kick *is* the resulting position.
        expect(a.position.x.abs(), lessThanOrEqualTo(bound + 1e-9));
        expect(a.position.y.abs(), lessThanOrEqualTo(bound + 1e-9));
        expect(a.position.z.abs(), lessThanOrEqualTo(bound + 1e-9));
      }
    });

    test('velocity kicks stay within the configured bound (per axis)', () {
      const bound = 0.75;
      const scatter = Scatter(positionBound: 0, velocityBound: bound, seed: 11);
      final input = _cluster(200); // zero initial velocity

      final out = scatter.apply(input);
      for (final a in out) {
        expect(a.velocity.x.abs(), lessThanOrEqualTo(bound + 1e-9));
        expect(a.velocity.y.abs(), lessThanOrEqualTo(bound + 1e-9));
        expect(a.velocity.z.abs(), lessThanOrEqualTo(bound + 1e-9));
      }
    });

    test('the kick adds to existing motion, it does not replace it', () {
      const scatter = Scatter(positionBound: 1, velocityBound: 1, seed: 3);
      final input = [
        _agent(position: Vector3(10, 20, 30), velocity: Vector3(1, 2, 3)),
      ];

      final out = scatter.apply(input).single;
      // Each component lands within one bound of where it started.
      expect((out.position - Vector3(10, 20, 30)).length, lessThanOrEqualTo(2));
      expect((out.velocity - Vector3(1, 2, 3)).length, lessThanOrEqualTo(2));
      // ...and actually moved (seed 3 draws non-zero kicks).
      expect(out.position, isNot(Vector3(10, 20, 30)));
    });

    test('the default scatter is a positional jolt only', () {
      const scatter = Scatter(seed: 5); // velocityBound defaults to 0
      final input = [_agent(velocity: Vector3(4, 5, 6))];

      final out = scatter.apply(input).single;
      expect(out.velocity, Vector3(4, 5, 6)); // velocity untouched
      expect(out.position, isNot(Vector3.zero())); // position kicked
    });

    test('zero bounds leave agents unmoved but still consume the stream', () {
      const scatter = Scatter(positionBound: 0, velocityBound: 0, seed: 9);
      final input = [
        _agent(position: Vector3(1, 2, 3), velocity: Vector3(4, 5, 6)),
        _agent(position: Vector3(-1, -2, -3)),
      ];

      final out = scatter.apply(input);
      expect(out[0].position, Vector3(1, 2, 3));
      expect(out[0].velocity, Vector3(4, 5, 6));
      expect(out[1].position, Vector3(-1, -2, -3));
    });

    test('carries voiceIndex and sends through untouched', () {
      const scatter = Scatter(positionBound: 1, seed: 1);
      final input = [
        SceneAgent(
          position: Vector3.zero(),
          voiceIndex: 4,
          sends: const {'reverb': 0.5},
        ),
      ];

      final out = scatter.apply(input).single;
      expect(out.voiceIndex, 4);
      expect(out.sends, {'reverb': 0.5});
    });

    test('returns fresh agents without mutating the source set', () {
      const scatter = Scatter(positionBound: 1, seed: 2);
      final source = _agent(position: Vector3(7, 7, 7));

      scatter.apply([source]);
      expect(source.position, Vector3(7, 7, 7)); // source is unchanged
    });

    test('an empty set disperses to an empty set', () {
      expect(const Scatter(seed: 1).apply(const []), isEmpty);
    });

    test('rejects a negative bound', () {
      expect(() => Scatter(positionBound: -1, seed: 0), throwsAssertionError);
      expect(() => Scatter(velocityBound: -1, seed: 0), throwsAssertionError);
    });
  });
}
