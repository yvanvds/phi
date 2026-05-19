/// Render [source] for the projected display.
///
/// Scaffold rule:
///   - drop lines whose first non-whitespace character is `#`
///     (full-line comments)
///   - collapse runs of two or more blank lines down to one
///   - leave inline `# …` tails alone — projecting a value alongside its
///     comment is sometimes the point
///
/// Alias expansion ("show the real verb behind the muscle-memory shortcut")
/// belongs with the DSL vocabulary and lands later — see phi-vision.md §6.
String stripForProjection(String source) {
  if (source.isEmpty) return source;
  final out = <String>[];
  var pendingBlank = false;
  for (final line in source.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('#')) continue;
    if (line.trim().isEmpty) {
      if (pendingBlank) continue;
      pendingBlank = true;
      out.add('');
      continue;
    }
    pendingBlank = false;
    out.add(line);
  }
  return out.join('\n');
}
