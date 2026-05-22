import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/state_machine/performance_state.dart';
import 'package:phi/domain/state_machine/performance_state_id.dart';

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
  });
}
