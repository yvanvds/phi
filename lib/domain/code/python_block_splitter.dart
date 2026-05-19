import 'python_block.dart';

/// Split [source] into one or more [PythonBlock]s.
///
/// Scaffold heuristic: a block opens on a non-blank top-level (indent-0)
/// line and absorbs every following non-blank line — including indented
/// continuations like a function body — until the next blank line. Blank
/// lines are separators and never belong to a block. The first non-blank
/// line of a block fixes its [PythonBlock.startLine]; the last non-blank
/// line fixes [PythonBlock.endLine].
///
/// This is intentionally not an AST split; the editor surface only needs
/// "what range does Ctrl+Enter evaluate" and "what does the projected
/// view group". Swap in a real parser when the DSL lands.
List<PythonBlock> splitIntoBlocks(String source) {
  if (source.isEmpty) return const [];
  final lines = source.split('\n');
  final blocks = <PythonBlock>[];
  int? blockStart;
  var blockEnd = -1;

  void flush() {
    if (blockStart == null) return;
    final slice = lines.sublist(blockStart!, blockEnd + 1).join('\n');
    blocks.add(
      PythonBlock(startLine: blockStart!, endLine: blockEnd, source: slice),
    );
    blockStart = null;
  }

  for (var i = 0; i < lines.length; i++) {
    final isBlank = lines[i].trim().isEmpty;
    if (isBlank) {
      flush();
      continue;
    }
    blockStart ??= i;
    blockEnd = i;
  }
  flush();
  return blocks;
}

/// Find the [PythonBlock] in [blocks] that contains the zero-indexed
/// [line]. Returns null if the line falls in a blank gap between blocks.
PythonBlock? blockAtLine(List<PythonBlock> blocks, int line) {
  for (final block in blocks) {
    if (line >= block.startLine && line <= block.endLine) return block;
  }
  return null;
}
