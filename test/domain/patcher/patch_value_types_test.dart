import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_connection.dart';
import 'package:phi/domain/patcher/patch_object_spec.dart';
import 'package:phi/domain/patcher/patch_point.dart';

void main() {
  group('PatchPoint', () {
    test('round-trips through JSON', () {
      const point = PatchPoint(12.5, -3.0);
      expect(PatchPoint.fromJson(point.toJson()), point);
    });

    test('missing coordinates default to the origin', () {
      expect(PatchPoint.fromJson(const {}), const PatchPoint(0, 0));
    });

    test('compares by value', () {
      expect(const PatchPoint(1, 2), const PatchPoint(1, 2));
      expect(const PatchPoint(1, 2), isNot(const PatchPoint(2, 1)));
    });
  });

  group('PatchConnection', () {
    const cable = PatchConnection(fromId: 3, outlet: 1, toId: 7, inlet: 0);

    test('round-trips through JSON', () {
      expect(PatchConnection.fromJson(cable.toJson()), cable);
    });

    test('toJson has the from/outlet/to/inlet shape', () {
      expect(cable.toJson(), {'from': 3, 'outlet': 1, 'to': 7, 'inlet': 0});
    });

    test('compares by value across all four fields', () {
      expect(
        cable,
        const PatchConnection(fromId: 3, outlet: 1, toId: 7, inlet: 0),
      );
      expect(
        cable,
        isNot(const PatchConnection(fromId: 3, outlet: 0, toId: 7, inlet: 0)),
      );
    });
  });

  group('PatchObjectSpec', () {
    const spec = PatchObjectSpec(
      type: '~sine',
      args: '440',
      position: PatchPoint(40, 20),
      params: {'freq': 440.0, 'gain': 0.5},
    );

    test('round-trips through JSON including params and position', () {
      expect(PatchObjectSpec.fromJson(spec.toJson()), spec);
    });

    test('emits params in sorted order so it re-encodes identically', () {
      const reordered = PatchObjectSpec(
        type: '~sine',
        args: '440',
        position: PatchPoint(40, 20),
        params: {'gain': 0.5, 'freq': 440.0},
      );
      expect(spec.toJson(), reordered.toJson());
      expect(spec, reordered);
    });

    test('defaults args/position/params when absent', () {
      final bare = PatchObjectSpec.fromJson(const {'type': '.slider'});
      expect(bare.type, '.slider');
      expect(bare.args, '');
      expect(bare.position, const PatchPoint(0, 0));
      expect(bare.params, isEmpty);
    });

    test('a missing type is a format error', () {
      expect(() => PatchObjectSpec.fromJson(const {}), throwsFormatException);
    });

    test('copyWith replaces only the given fields', () {
      final moved = spec.copyWith(position: const PatchPoint(0, 0));
      expect(moved.position, const PatchPoint(0, 0));
      expect(moved.type, spec.type);
      expect(moved.params, spec.params);
    });
  });
}
