import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/store/group_metadata.dart';

void main() {
  group('GroupMetadata', () {
    test('round-trips order and colour', () {
      const meta = GroupMetadata(order: ['b', 'a', 'c'], color: 'amber');
      final restored = GroupMetadata.fromJson(meta.toJson());
      expect(restored, meta);
    });

    test('omits empty fields from JSON', () {
      const meta = GroupMetadata(color: 'teal');
      expect(meta.toJson(), const {'color': 'teal'});
      const bare = GroupMetadata();
      expect(bare.toJson(), isEmpty);
    });

    test('isEmpty is true only with no order and no colour', () {
      expect(const GroupMetadata().isEmpty, isTrue);
      expect(const GroupMetadata(order: ['a']).isEmpty, isFalse);
      expect(const GroupMetadata(color: 'red').isEmpty, isFalse);
    });

    test('equality respects order sequence', () {
      expect(
        const GroupMetadata(order: ['a', 'b']),
        const GroupMetadata(order: ['a', 'b']),
      );
      expect(
        const GroupMetadata(order: ['a', 'b']) ==
            const GroupMetadata(order: ['b', 'a']),
        isFalse,
      );
    });
  });
}
