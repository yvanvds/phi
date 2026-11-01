import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/patcher/tutorial/patch_tutorial.dart';
import 'package:phi/domain/project/entity_address.dart';

/// The `.phitut.json` format (issue #489).
void main() {
  test('round-trips title, covers, summary and payload', () {
    final tutorial = PatchTutorial(
      title: 'metro',
      covers: const ['.metro'],
      summary: 'a pulse',
      payload: PatchPayload(
        dump: const {
          'object 0': {'ID': 0, 'type': '.metro', 'parms': '500'},
        },
        placement: EntityAddress.parse('mix.master'),
      ),
    );
    final back = PatchTutorial.fromJson(tutorial.toJson());
    expect(back.title, 'metro');
    expect(back.covers, ['.metro']);
    expect(back.summary, 'a pulse');
    expect(back.payload, tutorial.payload);
  });

  test('summary and covers are optional', () {
    final t = PatchTutorial.fromJson({
      'title': 'x',
      'payload': {'dump': <String, Object?>{}},
    });
    expect(t.covers, isEmpty);
    expect(t.summary, '');
    expect(t.payload, PatchPayload.empty);
  });

  test('a missing title or payload is a FormatException', () {
    expect(
      () => PatchTutorial.fromJson({'payload': <String, Object?>{}}),
      throwsFormatException,
    );
    expect(() => PatchTutorial.fromJson({'title': 'x'}), throwsFormatException);
  });
}
