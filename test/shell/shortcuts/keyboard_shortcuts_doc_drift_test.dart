import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/domain/shortcuts/shortcut_hint_section.dart';
import 'package:phi/shell/commands/shell_commands.dart';
import 'package:phi/shell/shortcuts/shortcut_catalog.dart';

/// Drift guard for the user docs' shortcut reference (issue #486): every
/// section of the [ShortcutCatalog] — the same tables the in-app keyboard
/// shortcuts overlay renders — must appear in `docs/user/keyboard-shortcuts.md`
/// as exactly the Markdown table [_tableFor] renders, under a `## <title>`
/// heading. A key added, dropped or renamed in code fails here until the page
/// follows; the failure message carries the table to paste.
void main() {
  const pagePath = 'docs/user/keyboard-shortcuts.md';

  test('every catalog section appears verbatim in $pagePath', () {
    final session = SessionState();
    addTearDown(session.dispose);
    // Every optional command wired, so each chord the full app registers is in
    // the Global section (the bare Phase-1 wiring omits some of them).
    void noop() {}
    final commands = buildShellCommands(
      session: session,
      onSummonSurface: (_) {},
      onUndo: noop,
      onRedo: noop,
      onCycleTabForward: noop,
      onCycleTabBackward: noop,
      onOpenCommandPalette: noop,
      onPanic: noop,
      onToggleLogPanel: noop,
      onOpenKeyboardShortcuts: noop,
      onCopyDiagnostics: noop,
      onNewProject: noop,
      onOpenProject: noop,
      onSaveProject: noop,
      onDuplicateProject: noop,
      onRenameProject: noop,
      onOpenSettings: noop,
      onOpenPatcherTutorial: noop,
      onExportPatchTutorial: noop,
    );

    final page = File(pagePath).readAsStringSync().replaceAll('\r\n', '\n');
    final sections = ShortcutCatalog.sections(commands: commands);
    expect(sections, isNotEmpty);

    for (final section in sections) {
      final heading = '## ${section.title}\n';
      expect(
        page.contains(heading),
        isTrue,
        reason: '$pagePath has no "## ${section.title}" heading',
      );
      final body = page.substring(page.indexOf(heading) + heading.length);
      final next = body.indexOf('\n## ');
      final sectionText = next < 0 ? body : body.substring(0, next);
      final table = _tableFor(section);
      // The table must end at a blank line (or the end of the page), so a
      // stale extra row after the generated ones fails too.
      expect(
        sectionText.contains('$table\n') || sectionText.endsWith(table),
        isTrue,
        reason:
            'The "${section.title}" table in $pagePath is out of date with '
            'the code. Replace it with:\n\n$table',
      );
    }
  });
}

/// The Markdown table for [section]: one row per hint, every key in backticks,
/// and a "When" column only when some hint in the section carries a note.
String _tableFor(ShortcutHintSection section) {
  String cell(String s) => s.replaceAll('|', r'\|');
  final withNotes = section.hints.any((h) => h.note != null);
  final out = StringBuffer()
    ..writeln(withNotes ? '| Keys | Action | When |' : '| Keys | Action |')
    ..writeln(withNotes ? '|---|---|---|' : '|---|---|');
  for (final hint in section.hints) {
    final keys = hint.keys.map((k) => '`${cell(k)}`').join(', ');
    out.write('| $keys | ${cell(hint.action)} |');
    if (withNotes) out.write(' ${cell(hint.note ?? '')} |');
    out.writeln();
  }
  return out.toString();
}
