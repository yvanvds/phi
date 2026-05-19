import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/code/python_block.dart';
import 'package:phi/domain/code/python_block_splitter.dart';

void main() {
  group('splitIntoBlocks', () {
    test('empty source produces no blocks', () {
      expect(splitIntoBlocks(''), isEmpty);
    });

    test('whitespace-only source produces no blocks', () {
      expect(splitIntoBlocks('\n\n  \n'), isEmpty);
    });

    test('single line is one block', () {
      final blocks = splitIntoBlocks('x = 1');
      expect(blocks, hasLength(1));
      expect(
        blocks.single,
        const PythonBlock(startLine: 0, endLine: 0, source: 'x = 1'),
      );
    });

    test('two top-level lines separated by blank are two blocks', () {
      final blocks = splitIntoBlocks('a = 1\n\nb = 2');
      expect(blocks, [
        const PythonBlock(startLine: 0, endLine: 0, source: 'a = 1'),
        const PythonBlock(startLine: 2, endLine: 2, source: 'b = 2'),
      ]);
    });

    test('indented continuation belongs to its outer block', () {
      const source = 'def foo():\n    return 1\n\nfoo()';
      final blocks = splitIntoBlocks(source);
      expect(blocks, hasLength(2));
      expect(blocks.first.startLine, 0);
      expect(blocks.first.endLine, 1);
      expect(blocks.first.source, 'def foo():\n    return 1');
      expect(blocks.last.startLine, 3);
      expect(blocks.last.endLine, 3);
      expect(blocks.last.source, 'foo()');
    });

    test('runs of blank lines do not produce empty blocks', () {
      final blocks = splitIntoBlocks('a\n\n\n\nb');
      expect(blocks.map((b) => b.source), ['a', 'b']);
    });

    test('trailing blank lines are ignored', () {
      final blocks = splitIntoBlocks('x = 1\n\n\n');
      expect(blocks, hasLength(1));
      expect(blocks.single.endLine, 0);
    });

    test('leading blank lines shift block start', () {
      final blocks = splitIntoBlocks('\n\nx = 1');
      expect(blocks.single.startLine, 2);
    });
  });

  group('blockAtLine', () {
    final blocks = splitIntoBlocks('a\n\nb\nc\n\nd');

    test('finds the block containing a line', () {
      expect(blockAtLine(blocks, 0)?.source, 'a');
      expect(blockAtLine(blocks, 2)?.source, 'b\nc');
      expect(blockAtLine(blocks, 3)?.source, 'b\nc');
      expect(blockAtLine(blocks, 5)?.source, 'd');
    });

    test('returns null inside a blank gap', () {
      expect(blockAtLine(blocks, 1), isNull);
      expect(blockAtLine(blocks, 4), isNull);
    });
  });
}
