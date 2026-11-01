import '../../domain/shortcuts/shortcut_hint.dart';
import '../../domain/shortcuts/shortcut_hint_section.dart';
import '../commands/command_search.dart';

/// Filters shortcut sections for the overlay's search field (issue #487),
/// matching the way the command palette does ([CommandSearch.score]).
///
/// A section whose title matches keeps every hint (typing `patcher` shows the
/// whole patcher table); otherwise a hint survives when the query matches its
/// action, any of its keys, or its note. Order is kept as declared — the tables
/// are read top to bottom, not ranked — and empty sections are dropped.
abstract final class ShortcutFilter {
  static List<ShortcutHintSection> run(
    String query,
    List<ShortcutHintSection> sections,
  ) {
    if (query.trim().isEmpty) return sections;
    final out = <ShortcutHintSection>[];
    for (final section in sections) {
      if (_matches(query, section.title)) {
        out.add(section);
        continue;
      }
      final hints = section.hints
          .where((h) => _hintMatches(query, h))
          .toList(growable: false);
      if (hints.isNotEmpty) {
        out.add(ShortcutHintSection(title: section.title, hints: hints));
      }
    }
    return out;
  }

  static bool _hintMatches(String query, ShortcutHint hint) =>
      _matches(query, hint.action) ||
      hint.keys.any((k) => _matches(query, k)) ||
      (hint.note != null && _matches(query, hint.note!));

  static bool _matches(String query, String text) =>
      CommandSearch.score(query, text) != null;
}
