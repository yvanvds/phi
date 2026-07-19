import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/voice/voice_codec.dart';
import 'package:phi/domain/voice/voice_definition.dart';

void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  group('VoiceCodec', () {
    const codec = VoiceCodec();

    test('declares schema version 1', () {
      expect(codec.version, 1);
    });

    test('encodes a VoiceDefinition to its JSON map', () {
      final voice = VoiceDefinition.internal(
        synth: addr('synth.bells'),
        output: addr('mix.perc'),
        color: 'amber',
      );
      expect(codec.encode(voice), {
        'kind': 'internal',
        'synth': 'synth.bells',
        'output': 'mix.perc',
        'color': 'amber',
      });
    });

    test('encodes a raw map by normalising through VoiceDefinition', () {
      // A stray key is dropped; the color defaults.
      expect(
        codec.encode(const {
          'kind': 'external',
          'channel': 5,
          'output': 'mix.master',
          'stray': true,
        }),
        {
          'kind': 'external',
          'channel': 5,
          'output': 'mix.master',
          'color': VoiceDefinition.defaultColor,
        },
      );
    });

    test('decode returns a normalised map', () {
      final map = {
        'kind': 'internal',
        'synth': 'synth.bells',
        'output': 'mix.perc',
        'color': 'voice1',
      };
      expect(codec.decode(map, 1), map);
    });

    test('null round-trips as null', () {
      expect(codec.encode(null), isNull);
      expect(codec.decode(null, 1), isNull);
    });
  });
}
