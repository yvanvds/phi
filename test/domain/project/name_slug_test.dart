import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/name_slug.dart';
import 'package:phi/domain/project/name_validator.dart';

void main() {
  group('NameSlug', () {
    test('lowercases and folds spaces to underscores', () {
      expect(NameSlug.of('phrase A'), 'phrase_a');
      expect(NameSlug.of('ch 1'), 'ch_1');
    });

    test('collapses runs of disallowed characters and trims underscores', () {
      expect(NameSlug.of('  Lead --- Line!!  '), 'lead_line');
    });

    test('prefixes a leading digit so the slug is a valid identifier', () {
      expect(NameSlug.of('808 kick'), '_808_kick');
    });

    test('nudges a Python keyword out of the way', () {
      expect(NameSlug.of('class'), 'class_');
      expect(NameValidator.isValid(NameSlug.of('class')), isTrue);
    });

    test('nudges a Windows reserved device name', () {
      expect(NameSlug.of('con'), 'con_');
      expect(NameValidator.isValid(NameSlug.of('con')), isTrue);
    });

    test('falls back when there are no usable characters', () {
      expect(NameSlug.of('***', fallback: 'channel'), 'channel');
      expect(NameSlug.of(''), 'item');
    });

    test('always produces a valid segment', () {
      for (final name in ['A B C', '  ', '99', 'lpt1', 'def', 'ünïcödé x']) {
        expect(
          NameValidator.isValid(NameSlug.of(name)),
          isTrue,
          reason: 'slug of "$name" should be valid',
        );
      }
    });

    test('truncates to the max segment length', () {
      final slug = NameSlug.of('a' * 100);
      expect(slug.length, lessThanOrEqualTo(NameValidator.maxLength));
      expect(NameValidator.isValid(slug), isTrue);
    });
  });
}
