import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/state_machine/state_snapshot.dart';

void main() {
  group('StateSnapshot', () {
    test('empty has no domains, no code blocks, no scene ref', () {
      const s = StateSnapshot.empty;
      expect(s.domainIds, isEmpty);
      expect(s.codeBlockIds, isEmpty);
      expect(s.sceneRef, isNull);
    });

    test('copyWith replaces only the supplied fields', () {
      const s = StateSnapshot(
        domainIds: ['bar.32'],
        codeBlockIds: ['drone'],
        sceneRef: 'pose-a',
      );

      final next = s.copyWith(codeBlockIds: ['drone', 'verse']);

      expect(next.domainIds, equals(['bar.32']));
      expect(next.codeBlockIds, equals(['drone', 'verse']));
      expect(next.sceneRef, 'pose-a');
    });

    test('copyWith with clearSceneRef nulls the scene ref', () {
      const s = StateSnapshot(sceneRef: 'pose-a');

      final next = s.copyWith(clearSceneRef: true);

      expect(next.sceneRef, isNull);
    });
  });
}
