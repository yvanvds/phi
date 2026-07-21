import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/code/code_script.dart';

void main() {
  group('CodeScript', () {
    test('toJson wraps the source under the "source" key', () {
      const script = CodeScript(source: 'a = 1\n');
      expect(script.toJson(), {'source': 'a = 1\n'});
    });

    test('fromJson∘toJson is byte-identical for tricky source', () {
      const source =
          '# comment "quoted" \'apostrophe\'\n'
          'x = "λ ∆ 🎹"\n'
          '\tindented = True\n\n\n'
          'print(x)\n';
      final restored = CodeScript.fromJson(
        const CodeScript(source: source).toJson(),
      );
      expect(restored.source, source);
    });

    test('a brand-new script defaults to empty source', () {
      expect(const CodeScript().source, '');
    });

    test('fromJson defaults a missing / non-string source to empty', () {
      expect(CodeScript.fromJson(const {}).source, '');
      expect(CodeScript.fromJson(const {'source': 42}).source, '');
    });

    test('value equality is by source', () {
      expect(const CodeScript(source: 'a'), const CodeScript(source: 'a'));
      expect(
        const CodeScript(source: 'a').hashCode,
        const CodeScript(source: 'a').hashCode,
      );
      expect(
        const CodeScript(source: 'a'),
        isNot(const CodeScript(source: 'b')),
      );
    });

    test('copyWith replaces the source', () {
      expect(const CodeScript(source: 'a').copyWith(source: 'b').source, 'b');
    });
  });
}
