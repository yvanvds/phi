import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/project/entity_address.dart';

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

  group('source placement (issue #220)', () {
    final bus = EntityAddress.parse('mix.reverb');

    test('an unplaced patch omits the placement key entirely', () {
      expect(PatchPayload(dump: dump).toJson(), {'dump': dump});
      expect(PatchPayload(dump: dump).placement, isNull);
    });

    test('placement round-trips through the JSON envelope', () {
      final placed = PatchPayload(dump: dump, placement: bus);
      expect(placed.toJson()['placement'], 'mix.reverb');
      final restored = PatchPayload.fromJson(placed.toJson());
      expect(restored, placed);
      expect(restored.placement, bus);
    });

    test('placement survives a real JSON string encode/decode', () {
      final placed = PatchPayload(dump: dump, placement: bus);
      final wire = jsonEncode(placed.toJson());
      final decoded = jsonDecode(wire) as Map<String, Object?>;
      expect(PatchPayload.fromJson(decoded), placed);
    });

    test('an unparseable placement degrades to unplaced', () {
      expect(
        PatchPayload.fromJson({'dump': dump, 'placement': 'not an address'}),
        PatchPayload(dump: dump),
      );
    });

    test('placement distinguishes otherwise-equal payloads', () {
      expect(
        PatchPayload(dump: dump, placement: bus),
        isNot(PatchPayload(dump: dump)),
      );
      expect(
        PatchPayload(dump: dump, placement: bus),
        isNot(
          PatchPayload(dump: dump, placement: EntityAddress.parse('mix.a')),
        ),
      );
    });

    test('withDump carries the placement over (the save path)', () {
      final placed = PatchPayload(placement: bus).withDump(dump);
      expect(placed.dump, dump);
      expect(placed.placement, bus);
    });

    test('withPlacement swaps the bus, carrying the dump over', () {
      final placed = PatchPayload(dump: dump).withPlacement(bus);
      expect(placed.placement, bus);
      expect(placed.dump, dump);
      expect(placed.withPlacement(null).placement, isNull);
    });
  });
}
