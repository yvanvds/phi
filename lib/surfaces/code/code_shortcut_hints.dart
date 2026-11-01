import '../../domain/shortcuts/shortcut_hint.dart';
import '../../domain/shortcuts/shortcut_hint_section.dart';

/// The Code surface's local shortcuts (issue #487), declared next to
/// `CodeEditorView`'s `Shortcuts` map.
///
/// FFI-free and Flutter-free: the shell's keyboard shortcuts overlay renders
/// [section], and the user docs (#486) are checked against it. Change it in the
/// same commit as the handler.
abstract final class CodeShortcutHints {
  static const ShortcutHintSection section = ShortcutHintSection(
    title: 'Code',
    hints: [
      ShortcutHint(
        keys: ['Ctrl+Enter'],
        action: 'Evaluate the block under the cursor',
        note: 'editor focused',
      ),
    ],
  );
}
