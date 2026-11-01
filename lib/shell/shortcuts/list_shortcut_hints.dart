import '../../domain/shortcuts/shortcut_hint.dart';
import '../../domain/shortcuts/shortcut_hint_section.dart';

/// Keys shared by the shell's pick-lists — the command palette, this overlay's
/// own filter and `PhiSelect` dropdowns (issue #487). Declared beside the
/// palette's key handler; FFI-free so the user docs (#486) can read it.
abstract final class ListShortcutHints {
  static const ShortcutHintSection section = ShortcutHintSection(
    title: 'Lists & dialogs',
    hints: [
      ShortcutHint(keys: ['Up', 'Down'], action: 'Move the highlight'),
      ShortcutHint(
        keys: ['Enter', 'Space'],
        action: 'Run / pick the highlighted entry',
        note: 'Space in a select only',
      ),
      ShortcutHint(keys: ['Tab'], action: 'Move to the next control'),
      ShortcutHint(keys: ['Esc'], action: 'Close without picking'),
    ],
  );
}
