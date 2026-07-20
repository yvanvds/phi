import 'package:flutter_test/flutter_test.dart';
import 'package:phi/shell/commands/command_match.dart';
import 'package:phi/shell/commands/command_search.dart';
import 'package:phi/shell/commands/phi_command.dart';

/// Unit tests for the pure command-palette ranking (design
/// `docs/design/shell-layout.md` §4): fuzzy matching over title + category,
/// recently-used ordering, and enabled-predicate filtering.
void main() {
  PhiCommand cmd(
    String id,
    String title, {
    String category = 'General',
    bool Function()? isEnabled,
  }) => PhiCommand(
    id: id,
    title: title,
    category: category,
    invoke: () {},
    isEnabled: isEnabled,
  );

  List<String> ids(Iterable<CommandMatch> matches) => [
    for (final m in matches) m.command.id,
  ];

  group('empty query', () {
    test('returns every enabled command, recents first then registration', () {
      final commands = [
        cmd('a', 'Alpha'),
        cmd('b', 'Bravo'),
        cmd('c', 'Charlie'),
      ];

      final results = CommandSearch.run('', commands, recentIds: ['c', 'a']);

      // Recents in recency order (c newest), then the rest in registration order.
      expect(ids(results), ['c', 'a', 'b']);
    });

    test('with no recents keeps registration order', () {
      final commands = [cmd('a', 'Alpha'), cmd('b', 'Bravo')];
      expect(ids(CommandSearch.run('', commands)), ['a', 'b']);
    });

    test('whitespace-only query is treated as empty', () {
      final commands = [cmd('a', 'Alpha'), cmd('b', 'Bravo')];
      final results = CommandSearch.run('   ', commands, recentIds: ['b']);
      expect(ids(results), ['b', 'a']);
    });
  });

  group('fuzzy matching', () {
    test('matches a subsequence and drops non-matches', () {
      final commands = [
        cmd('play', 'Play'),
        cmd('stop', 'Stop'),
        cmd('save', 'Save Project'),
      ];

      final results = CommandSearch.run('sp', commands);

      // "sp" is a subsequence of "Save Project" and "Stop", but not "Play".
      expect(ids(results), containsAll(['save', 'stop']));
      expect(ids(results), isNot(contains('play')));
    });

    test('ranks a word-start prefix above a mid-word match', () {
      final commands = [cmd('midword', 'Remix'), cmd('prefix', 'Mix')];

      // "mi" is a contiguous prefix of "Mix" but sits mid-word in "Remix"; the
      // prefix (word-start) match wins.
      final results = CommandSearch.run('mi', commands);
      expect(results.first.command.id, 'prefix');
    });

    test('reports matched title indices for highlighting', () {
      final results = CommandSearch.run('mi', [cmd('m', 'Mix')]);
      expect(results.single.matchedTitleIndices, {0, 1});
    });

    test('matches against the category, scored below a title hit', () {
      final commands = [
        cmd('t', 'Rewind', category: 'Transport'),
        cmd('x', 'Transpose', category: 'Edit'),
      ];

      final results = CommandSearch.run('trans', commands);
      // Both surface (title hit on Transpose, category hit on Rewind)…
      expect(ids(results), containsAll(['t', 'x']));
      // …but the title match outranks the category-only match.
      expect(results.first.command.id, 'x');
      // A category-only match carries no title highlight.
      final rewind = results.firstWhere((m) => m.command.id == 't');
      expect(rewind.matchedTitleIndices, isEmpty);
    });

    test('ties break toward the more recently used', () {
      final commands = [cmd('a', 'Scene'), cmd('b', 'Scene')];
      // Identical titles → identical score; recents decides.
      final results = CommandSearch.run('scene', commands, recentIds: ['b']);
      expect(results.first.command.id, 'b');
    });
  });

  group('enabled-predicate filtering', () {
    test('a disabled command never appears (empty query)', () {
      final commands = [
        cmd('on', 'Enabled'),
        cmd('off', 'Disabled', isEnabled: () => false),
      ];
      expect(ids(CommandSearch.run('', commands)), ['on']);
    });

    test('a disabled command never appears (matching query)', () {
      final commands = [
        cmd('stop', 'Stop', isEnabled: () => false),
        cmd('scene', 'Scene'),
      ];
      // "s" matches both, but the disabled Stop is hidden.
      expect(ids(CommandSearch.run('s', commands)), ['scene']);
    });
  });
}
