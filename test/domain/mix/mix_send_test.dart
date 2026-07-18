import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/mix/mix_send.dart';
import 'package:phi/domain/project/entity_address.dart';

void main() {
  EntityAddress mix(String dotted) => EntityAddress.parse('mix.$dotted');

  group('MixSend', () {
    test('round-trips through JSON', () {
      final send = MixSend(to: mix('verb'), level: 0.4, preFader: true);
      expect(MixSend.fromJson(send.toJson()), send);
    });

    test('toJson writes the target as a dotted address string', () {
      expect(MixSend(to: mix('verb'), level: 0.4).toJson(), {
        'to': 'mix.verb',
        'level': 0.4,
        'preFader': false,
      });
    });

    test('defaults are unity level, post-fader', () {
      final send = MixSend(to: mix('verb'));
      expect(send.level, 1.0);
      expect(send.preFader, isFalse);
    });

    test('fromJson defaults level and preFader for a sparse map', () {
      final send = MixSend.fromJson(const {'to': 'mix.verb'});
      expect(send.to, mix('verb'));
      expect(send.level, 1.0);
      expect(send.preFader, isFalse);
    });

    test('copyWith replaces only the given fields', () {
      final send = MixSend(to: mix('verb'), level: 0.4);
      expect(send.copyWith(level: 0.9), MixSend(to: mix('verb'), level: 0.9));
      expect(
        send.copyWith(to: mix('echo')),
        MixSend(to: mix('echo'), level: 0.4),
      );
    });

    test('equality is by value across every field', () {
      expect(MixSend(to: mix('verb')), MixSend(to: mix('verb')));
      expect(MixSend(to: mix('verb')), isNot(MixSend(to: mix('echo'))));
      expect(
        MixSend(to: mix('verb'), level: 0.4),
        isNot(MixSend(to: mix('verb'), level: 0.5)),
      );
      expect(
        MixSend(to: mix('verb'), preFader: true),
        isNot(MixSend(to: mix('verb'))),
      );
    });

    test('a send with no target is a format error', () {
      expect(() => MixSend.fromJson(const {}), throwsA(isA<TypeError>()));
      expect(
        () => MixSend.fromJson(const {'to': 'not an address'}),
        throwsFormatException,
      );
    });
  });
}
