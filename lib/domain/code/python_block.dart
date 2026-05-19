/// A contiguous range of Python source lines treated as a single
/// evaluation unit.
///
/// Lines are zero-indexed. [startLine] is inclusive, [endLine] is
/// inclusive — a single-line block has `startLine == endLine`. [source]
/// is the original text of those lines joined by `'\n'` without a
/// trailing newline.
class PythonBlock {
  const PythonBlock({
    required this.startLine,
    required this.endLine,
    required this.source,
  });

  final int startLine;
  final int endLine;
  final String source;

  int get lineCount => endLine - startLine + 1;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PythonBlock &&
          other.startLine == startLine &&
          other.endLine == endLine &&
          other.source == source);

  @override
  int get hashCode => Object.hash(startLine, endLine, source);

  @override
  String toString() => 'PythonBlock($startLine..$endLine)';
}
