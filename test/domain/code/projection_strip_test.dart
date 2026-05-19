import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/code/projection_strip.dart';

void main() {
  group('stripForProjection', () {
    test('empty source returns empty', () {
      expect(stripForProjection(''), '');
    });

    test('source with no comments returns unchanged', () {
      const source = 'a = 1\nb = 2';
      expect(stripForProjection(source), source);
    });

    test('drops full-line comments', () {
      const source = '# top note\na = 1\n  # indented note\nb = 2';
      expect(stripForProjection(source), 'a = 1\nb = 2');
    });

    test('keeps inline comments', () {
      const source = 'a = 1  # keep me\nb = 2';
      expect(stripForProjection(source), source);
    });

    test('collapses runs of blank lines to one', () {
      const source = 'a\n\n\n\nb';
      expect(stripForProjection(source), 'a\n\nb');
    });

    test('drops comment then collapses surrounding blanks', () {
      const source = 'a\n\n# divider\n\nb';
      expect(stripForProjection(source), 'a\n\nb');
    });
  });
}
