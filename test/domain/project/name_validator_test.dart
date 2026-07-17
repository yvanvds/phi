import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/name_problem.dart';
import 'package:phi/domain/project/name_validator.dart';

void main() {
  group('valid names', () {
    for (final name in const [
      'a',
      '_',
      'drums',
      'intro_fill',
      'lead_line_2',
      '_private',
      'x1',
      'com',
      'com0',
      'com10',
      'lpt0',
      'console',
      'nul_ish',
      'match', // a Python soft keyword — an ordinary identifier
      'case',
      'type',
      'true', // lowercase, so not the Python keyword `True`
      'none',
      'false',
    ]) {
      test('"$name" is accepted', () {
        expect(NameValidator.check(name), isNull);
        expect(NameValidator.isValid(name), isTrue);
      });
    }

    test('a 64-character name is accepted', () {
      expect(NameValidator.isValid('a' * 64), isTrue);
    });
  });

  group('shape', () {
    test('empty is rejected', () {
      expect(NameValidator.check(''), NameProblem.empty);
    });

    test('a 65-character name is too long', () {
      expect(NameValidator.check('a' * 65), NameProblem.tooLong);
    });

    for (final name in const [
      'Drums', // uppercase
      'intro-fill', // hyphen
      'intro fill', // space
      '1st', // leading digit
      'café', // non-ASCII
      'a.b', // a dot is a separator, never part of a segment
      'name!',
    ]) {
      test('"$name" is malformed', () {
        expect(NameValidator.check(name), NameProblem.malformed);
      });
    }
  });

  group('python keywords', () {
    for (final kw in const [
      'class',
      'for',
      'def',
      'return',
      'import',
      'lambda',
    ]) {
      test('"$kw" is rejected as a Python keyword', () {
        expect(NameValidator.check(kw), NameProblem.pythonKeyword);
      });
    }
  });

  group('windows reserved device names', () {
    for (final name in const [
      'con',
      'prn',
      'aux',
      'nul',
      'com1',
      'com9',
      'lpt1',
      'lpt9',
    ]) {
      test('"$name" is rejected as a reserved device name', () {
        expect(NameValidator.check(name), NameProblem.reservedDeviceName);
      });
    }
  });

  test('every NameProblem carries a non-empty message', () {
    for (final problem in NameProblem.values) {
      expect(problem.message, isNotEmpty);
    }
  });
}
