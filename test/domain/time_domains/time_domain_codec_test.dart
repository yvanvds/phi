import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/time_domains/time_domain.dart';
import 'package:phi/domain/time_domains/time_domain_codec.dart';

void main() {
  group('TimeDomainCodec', () {
    const codec = TimeDomainCodec();

    test('declares schema version 1', () {
      expect(codec.version, 1);
    });

    test('round-trips a domain (name + tempo)', () {
      const domain = TimeDomain(name: 'drum', tempo: 124);
      final decoded = codec.decode(codec.encode(domain), 1)! as TimeDomain;
      expect(decoded, domain);
    });

    test('encodes to a JSON map carrying the name and tempo', () {
      expect(codec.encode(const TimeDomain(name: 'drum', tempo: 124)), {
        'name': 'drum',
        'tempo': 124.0,
      });
    });

    test('null round-trips as null', () {
      expect(codec.encode(null), isNull);
      expect(codec.decode(null, 1), isNull);
    });
  });
}
