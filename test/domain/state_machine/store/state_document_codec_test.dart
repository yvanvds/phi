import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/state_machine/store/state_document.dart';
import 'package:phi/domain/state_machine/store/state_document_codec.dart';
import 'package:phi/domain/state_machine/store/state_transition_spec.dart';

void main() {
  const codec = StateDocumentCodec();

  StateDocument document() => StateDocument(
    position: const Offset(160, 160),
    transitions: [StateTransitionSpec(to: EntityAddress.parse('state.verse'))],
  );

  test('writes schema version 1', () {
    expect(codec.version, 1);
  });

  test('encode flattens a live document and passes a stored map through '
      'normalised', () {
    final fromDocument = codec.encode(document());
    final fromMap = codec.encode(document().toJson());
    expect(fromDocument, document().toJson());
    expect(fromMap, document().toJson());
  });

  test('decode round-trips the payload identity (map-native)', () {
    final decoded = codec.decode(document().toJson(), 1);
    // The stored payload stays a JSON map (the journal contract) …
    expect(decoded, isA<Map<String, Object?>>());
    // … and rebuilds the identical document.
    expect(StateDocument.fromJson((decoded! as Map).cast()), document());
  });

  test('null payloads pass through', () {
    expect(codec.encode(null), isNull);
    expect(codec.decode(null, 1), isNull);
  });

  test('a corrupt payload fails loudly', () {
    expect(
      () => codec.decode(const {
        'transitions': [
          {'to': 'nope'},
        ],
      }, 1),
      throwsFormatException,
    );
  });
}
