import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/scene/box_volume.dart';
import 'package:phi/domain/scene/sphere_volume.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  group('SphereVolume', () {
    SphereVolume make() => SphereVolume(
      center: Vector3(1, 2, 3),
      radius: 2,
      effect: 'reverb',
      send: 0.5,
    );

    test('carries its effect payload', () {
      final v = make();
      expect(v.effect, 'reverb');
      expect(v.send, 0.5);
    });

    test('contains points inside the radius', () {
      final v = make();
      expect(v.contains(Vector3(1, 2, 3)), isTrue); // centre
      expect(v.contains(Vector3(2.5, 2, 3)), isTrue); // 1.5 away
    });

    test('a point exactly on the surface counts as inside', () {
      final v = make();
      expect(v.contains(Vector3(3, 2, 3)), isTrue); // exactly radius 2 away
    });

    test('excludes points beyond the radius', () {
      final v = make();
      expect(v.contains(Vector3(4, 2, 3)), isFalse); // 3 away
    });

    test('copies its centre so the caller cannot mutate it', () {
      final center = Vector3(1, 2, 3);
      final v = SphereVolume(center: center, radius: 1, effect: 'x', send: 1);
      center.x = 99;
      expect(v.center, Vector3(1, 2, 3));
    });
  });

  group('BoxVolume', () {
    BoxVolume make() => BoxVolume(
      corner: Vector3(0, 0, 0),
      opposite: Vector3(2, 2, 2),
      effect: 'delay',
      send: 0.8,
    );

    test('carries its effect payload', () {
      final v = make();
      expect(v.effect, 'delay');
      expect(v.send, 0.8);
    });

    test('contains points inside the box', () {
      final v = make();
      expect(v.contains(Vector3(1, 1, 1)), isTrue);
    });

    test('is inclusive on every face', () {
      final v = make();
      expect(v.contains(Vector3(0, 0, 0)), isTrue);
      expect(v.contains(Vector3(2, 2, 2)), isTrue);
      expect(v.contains(Vector3(0, 1, 2)), isTrue);
    });

    test('excludes points outside any axis', () {
      final v = make();
      expect(v.contains(Vector3(3, 1, 1)), isFalse);
      expect(v.contains(Vector3(1, -0.1, 1)), isFalse);
      expect(v.contains(Vector3(1, 1, 2.5)), isFalse);
    });

    test('normalises corners passed in any order', () {
      final v = BoxVolume(
        corner: Vector3(2, 2, 2),
        opposite: Vector3(0, 0, 0),
        effect: 'x',
        send: 1,
      );
      expect(v.min, Vector3(0, 0, 0));
      expect(v.max, Vector3(2, 2, 2));
      expect(v.contains(Vector3(1, 1, 1)), isTrue);
    });
  });
}
