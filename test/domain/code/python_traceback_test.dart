import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/code/python_traceback.dart';

void main() {
  group('PythonTraceback.parse', () {
    test('pulls the line number from a single <script> frame', () {
      const raw =
          'Traceback (most recent call last):\n'
          '  File "<script>", line 3, in <module>\n'
          "NameError: name 'x' is not defined";
      final tb = PythonTraceback.parse(raw);

      expect(tb.scriptLine, 3);
      expect(tb.hasScriptLine, isTrue);
      expect(tb.text, raw);
    });

    test('takes the innermost <script> frame when several are present', () {
      const raw =
          'Traceback (most recent call last):\n'
          '  File "<script>", line 5, in <module>\n'
          '  File "<script>", line 2, in gain\n'
          'ZeroDivisionError: division by zero';
      final tb = PythonTraceback.parse(raw);

      // Line 2 is where the exception was actually raised (inside `gain`).
      expect(tb.scriptLine, 2);
    });

    test('leaves scriptLine null for a callback-origin traceback', () {
      const raw =
          'Traceback (most recent call last):\n'
          '  File "phi/__init__.py", line 120, in _tick\n'
          'RuntimeError: callback boom';
      final tb = PythonTraceback.parse(raw);

      expect(tb.scriptLine, isNull);
      expect(tb.hasScriptLine, isFalse);
      // Still carried verbatim so the strip can render it in full.
      expect(tb.text, raw);
    });

    test('trims trailing whitespace but keeps the body verbatim', () {
      const raw = 'SyntaxError: invalid syntax\n\n';
      final tb = PythonTraceback.parse(raw);

      expect(tb.text, 'SyntaxError: invalid syntax');
      expect(tb.scriptLine, isNull);
    });

    test('summary is the last non-empty line', () {
      const raw =
          'Traceback (most recent call last):\n'
          '  File "<script>", line 1, in <module>\n'
          "KeyError: 'bells'\n";
      final tb = PythonTraceback.parse(raw);

      expect(tb.summary, "KeyError: 'bells'");
    });

    test('value equality holds for identical parses', () {
      const raw = '  File "<script>", line 7, in <module>\nOops';
      expect(PythonTraceback.parse(raw), PythonTraceback.parse(raw));
    });
  });
}
