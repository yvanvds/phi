import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/state_machine/state_node_data.dart';

/// The immutable canvas node row the registry-backed controller derives from
/// a `state.` entity (issue #241).
void main() {
  final intro = EntityAddress.parse('state.intro');
  final verse = EntityAddress.parse('state.verse');

  group('StateNodeData', () {
    test('is a value: equality over address, voice and position', () {
      const position = Offset(160, 160);
      final a = StateNodeData(address: intro, voice: 1, position: position);
      final b = StateNodeData(address: intro, voice: 1, position: position);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(StateNodeData(address: verse, voice: 1, position: position)),
      );
      expect(
        a,
        isNot(StateNodeData(address: intro, voice: 2, position: position)),
      );
      expect(
        a,
        isNot(StateNodeData(address: intro, voice: 1, position: Offset.zero)),
      );
    });

    test('the display name is the address leaf', () {
      final node = StateNodeData(
        address: EntityAddress.parse('state.outro'),
        voice: 3,
        position: Offset.zero,
      );
      expect(node.name, 'outro');
    });
  });
}
