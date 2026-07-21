/// A parsed Python traceback delivered by the engine's script error channel
/// (`LiveCoding.errors`, design `docs/design/live-coding.md` §5).
///
/// Each uncaught exception or syntax error arrives as one formatted traceback
/// string. The engine compiles every evaluated block under the filename
/// `"<script>"`, so a frame that originates in user code reads
/// `File "<script>", line N`. [parse] pulls the **innermost** such line — the
/// actual error site in the just-run block — into [scriptLine]; the full text
/// is kept verbatim in [text] so a traceback with no `<script>` frame (a
/// scheduled-callback error firing later, deep in library code) still renders
/// in full.
///
/// Pure Dart — the strip widget renders it, the surface maps [scriptLine] back
/// onto an editor line, but the parsing itself carries no Flutter dependency.
class PythonTraceback {
  const PythonTraceback({required this.text, this.scriptLine});

  /// Parse a raw engine traceback [raw] into a [PythonTraceback], extracting the
  /// innermost `File "<script>", line N` line number when present.
  factory PythonTraceback.parse(String raw) {
    int? line;
    for (final match in _scriptFrame.allMatches(raw)) {
      // Keep overwriting: the last match is the innermost frame — the site the
      // exception was actually raised at in the user's block.
      line = int.tryParse(match.group(1)!);
    }
    return PythonTraceback(text: raw.trimRight(), scriptLine: line);
  }

  /// The traceback verbatim, exactly as the engine delivered it (trailing
  /// whitespace trimmed). Rendered in full by the error strip.
  final String text;

  /// The 1-indexed line **within the submitted script** of the innermost
  /// `File "<script>", line N` frame, or `null` when the traceback carries no
  /// such frame (a callback-origin error, or one raised before any user line —
  /// a bare syntax error, say). `null` is the "no matching editor line" signal
  /// the surface uses to render the strip without moving the eval flash.
  final int? scriptLine;

  /// Matches a CPython traceback frame whose file is the engine's `<script>`
  /// sentinel, capturing the line number: `File "<script>", line 12`.
  static final RegExp _scriptFrame = RegExp(r'File "<script>", line (\d+)');

  /// Whether a `<script>` line was found — i.e. the error can be traced to a
  /// line of the evaluated block.
  bool get hasScriptLine => scriptLine != null;

  /// The last non-empty line of [text] — the `ExceptionType: message` summary
  /// Python prints last. Empty when the traceback is blank.
  String get summary {
    for (final line in text.split('\n').reversed) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  @override
  bool operator ==(Object other) =>
      other is PythonTraceback &&
      other.text == text &&
      other.scriptLine == scriptLine;

  @override
  int get hashCode => Object.hash(text, scriptLine);

  @override
  String toString() => 'PythonTraceback(scriptLine: $scriptLine)';
}
