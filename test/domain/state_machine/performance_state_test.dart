import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/state_machine/performance_state.dart';
import 'package:phi/domain/state_machine/performance_state_id.dart';
import 'package:phi/domain/state_machine/state_snapshot.dart';

void main() {
  group('PerformanceState', () {
    test('moveTo notifies only when position actually changes', () {
      final s = PerformanceState(
        id: const PerformanceStateId('a'),
        name: 'intro',
        voice: 1,
        position: Offset.zero,
      );
      var ticks = 0;
      s.addListener(() => ticks++);

      s.moveTo(const Offset(48, 48));
      s.moveTo(const Offset(48, 48));

      expect(s.position, const Offset(48, 48));
      expect(ticks, 1);
    });

    test('rename trims, ignores empty, ignores unchanged', () {
      final s = PerformanceState(
        id: const PerformanceStateId('a'),
        name: 'intro',
        voice: 1,
        position: Offset.zero,
      );
      var ticks = 0;
      s.addListener(() => ticks++);

      s.rename('  ');
      s.rename('intro');
      s.rename('verse  ');

      expect(s.name, 'verse');
      expect(ticks, 1);
    });

    test('snapshot defaults to empty', () {
      final s = PerformanceState(
        id: const PerformanceStateId('a'),
        name: 'intro',
        voice: 1,
        position: Offset.zero,
      );

      expect(s.snapshot.domainIds, isEmpty);
      expect(s.snapshot.codeBlockIds, isEmpty);
      expect(s.snapshot.sceneRef, isNull);
    });

    test('setSnapshot notifies and replaces the snapshot', () {
      final s = PerformanceState(
        id: const PerformanceStateId('a'),
        name: 'intro',
        voice: 1,
        position: Offset.zero,
      );
      var ticks = 0;
      s.addListener(() => ticks++);

      const next = StateSnapshot(domainIds: ['bar.32']);
      s.setSnapshot(next);

      expect(s.snapshot.domainIds, equals(['bar.32']));
      expect(ticks, 1);
    });

    test('setSnapshot is idempotent for the identical instance', () {
      const seeded = StateSnapshot(sceneRef: 'pose-a');
      final s = PerformanceState(
        id: const PerformanceStateId('a'),
        name: 'intro',
        voice: 1,
        position: Offset.zero,
        snapshot: seeded,
      );
      var ticks = 0;
      s.addListener(() => ticks++);

      s.setSnapshot(seeded);

      expect(ticks, 0);
    });
  });
}
