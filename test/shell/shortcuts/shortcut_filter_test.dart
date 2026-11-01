import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/shortcuts/shortcut_hint.dart';
import 'package:phi/domain/shortcuts/shortcut_hint_section.dart';
import 'package:phi/shell/shortcuts/shortcut_filter.dart';

void main() {
  const sections = [
    ShortcutHintSection(
      title: 'Patcher',
      hints: [
        ShortcutHint(keys: ['Ctrl+E'], action: 'Toggle edit ↔ run mode'),
        ShortcutHint(keys: ['Ctrl+0'], action: 'Frame the whole patch'),
      ],
    ),
    ShortcutHintSection(
      title: 'Code',
      hints: [
        ShortcutHint(
          keys: ['Ctrl+Enter'],
          action: 'Evaluate the block',
          note: 'editor focused',
        ),
      ],
    ),
  ];

  List<String> actions(List<ShortcutHintSection> s) => [
    for (final section in s)
      for (final h in section.hints) h.action,
  ];

  test('an empty query keeps everything', () {
    expect(ShortcutFilter.run('  ', sections), same(sections));
  });

  test('matches the action fuzzily, keeping declared order', () {
    final out = ShortcutFilter.run('frame', sections);
    expect(out.map((s) => s.title), ['Patcher']);
    expect(actions(out), ['Frame the whole patch']);
  });

  test('matches a chord', () {
    expect(actions(ShortcutFilter.run('ctrl+0', sections)), [
      'Frame the whole patch',
    ]);
  });

  test('matches a note', () {
    expect(actions(ShortcutFilter.run('focused', sections)), [
      'Evaluate the block',
    ]);
  });

  test('a section-title match keeps the whole section', () {
    final out = ShortcutFilter.run('patcher', sections);
    expect(out.map((s) => s.title), ['Patcher']);
    expect(out.single.hints, hasLength(2));
  });

  test('no match drops every section', () {
    expect(ShortcutFilter.run('zzzz', sections), isEmpty);
  });
}
