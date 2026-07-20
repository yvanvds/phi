import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_payload.dart';

void main() {
  // A representative engine dump — the exact shape is opaque to Phi; it only
  // carries it. Nested maps/lists exercise the deep round-trip.
  final dump = <String, Object?>{
    'objects': [
      {'id': 1, 'type': '~sine', 'x': 40.0, 'y': 20.0, 'args': '440'},
      {'id': 2, 'type': '~dac', 'x': 200.0, 'y': 20.0},
    ],
    'cables': [
      {'from': 1, 'outlet': 0, 'to': 2, 'inlet': 0},
    ],
    'meta': {'version': 3, 'name': 'demo'},
  };

  test('toJson wraps the dump under a "dump" key', () {
    expect(PatchPayload(dump: dump).toJson(), {'dump': dump});
  });

  test('fromJson round-trips identity through the JSON envelope', () {
    final original = PatchPayload(dump: dump);
    final restored = PatchPayload.fromJson(original.toJson());
    expect(restored, original);
    expect(restored.dump, dump);
  });

  test('survives a real JSON string encode/decode', () {
    final original = PatchPayload(dump: dump);
    final wire = jsonEncode(original.toJson());
    final decoded = jsonDecode(wire) as Map<String, Object?>;
    expect(PatchPayload.fromJson(decoded), original);
  });

  test('equality is structural and order-independent over the dump', () {
    const a = PatchPayload(dump: {'a': 1, 'b': 2});
    const b = PatchPayload(dump: {'b': 2, 'a': 1});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('unequal dumps are not equal', () {
    const a = PatchPayload(dump: {'objects': 1});
    const b = PatchPayload(dump: {'objects': 2});
    expect(a, isNot(b));
  });

  test('empty is a patch with no dump content', () {
    expect(PatchPayload.empty.dump, isEmpty);
    expect(PatchPayload.fromJson(const {}), PatchPayload.empty);
    expect(PatchPayload.fromJson(const {'dump': null}), PatchPayload.empty);
  });

  test('withDump swaps in a fresh dump (the save path)', () {
    final refreshed = PatchPayload.empty.withDump(dump);
    expect(refreshed.dump, dump);
    expect(refreshed, PatchPayload(dump: dump));
  });
}
