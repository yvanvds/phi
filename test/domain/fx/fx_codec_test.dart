import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/fx/fx_codec.dart';
import 'package:phi/domain/fx/fx_definition.dart';
import 'package:phi/domain/fx/fx_kind.dart';

void main() {
  group('FxCodec', () {
    const codec = FxCodec();

    test('declares schema version 1', () {
      expect(codec.version, 1);
    });

    test('encodes an FxDefinition to its JSON map', () {
      expect(
        codec.encode(
          const FxDefinition(
            kind: FxKind.ringModulator,
            params: {'freq': 440.0},
          ),
        ),
        {
          'kind': 'ringModulator',
          'params': {'freq': 440.0},
        },
      );
    });

    test('encodes a raw map by normalising through FxDefinition', () {
      final encoded = codec.encode(const {
        'kind': 'phaser',
        'params': {'rate': 0.2},
        'stray': 1,
      });
      expect(
        encoded,
        const FxDefinition(kind: FxKind.phaser, params: {'rate': 0.2}).toJson(),
      );
    });

    test('decode returns a normalised map', () {
      final map = {'kind': 'difference', 'params': <String, Object?>{}};
      expect(codec.decode(map, 1), map);
    });

    test('null round-trips as null', () {
      expect(codec.encode(null), isNull);
      expect(codec.decode(null, 1), isNull);
    });
  });
}
