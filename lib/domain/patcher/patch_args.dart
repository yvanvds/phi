/// Split a patcher object's creation-argument string into its positional
/// arguments.
///
/// The engine takes creation parameters as **one whitespace-separated string**
/// (yse's `setParams`), so every reader of a node's arguments — the params
/// dialog seeding its fields, the reference panel showing what a selected node
/// is set to, the default node body printing them — has to cut it the same way,
/// or the *n*th value and the *n*th documented parameter drift apart.
///
/// Runs of whitespace count as one separator, and an empty (or blank) string
/// yields no arguments rather than one empty argument.
List<String> splitPatchArgs(String args) {
  final trimmed = args.trim();
  return trimmed.isEmpty ? const [] : trimmed.split(RegExp(r'\s+'));
}
