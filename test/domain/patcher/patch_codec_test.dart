import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_codec.dart';
import 'package:phi/domain/patcher/patch_payload.dart';

void main() {
  const codec = PatchCodec();

  final dump = <String, Object?>{
    'objects': [
      {'id': 1, 'type': '~sine'},
    ],
    'cables': const [],
  };

  test('declares schema v1', () {
    expect(codec.version, 1);
  });

  test('encodes a PatchPayload to its JSON map', () {
    expect(codec.encode(PatchPayload(dump: dump)), {'dump': dump});
  });

  test('encode normalises an already-JSON map through PatchPayload', () {
    expect(codec.encode({'dump': dump}), {'dump': dump});
  });

  test('decode rebuilds a normalised JSON map', () {
    final decoded = codec.decode({'dump': dump}, 1);
    expect(decoded, {'dump': dump});
  });

  test('null payloads pass through as null', () {
    expect(codec.encode(null), isNull);
    expect(codec.decode(null, 1), isNull);
  });

  test('a partial map decodes to an empty patch', () {
    expect(codec.decode(const <String, Object?>{}, 1), {
      'dump': const <String, Object?>{},
    });
  });
}
