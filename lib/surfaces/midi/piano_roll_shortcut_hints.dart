import '../../domain/shortcuts/shortcut_hint.dart';
import '../../domain/shortcuts/shortcut_hint_section.dart';

/// The MIDI surface's local shortcuts (issue #487), declared next to the piano
/// roll's handlers (`PianoRollEditor._onKey` and its pointer-signal zoom).
///
/// FFI-free and Flutter-free: the shell's keyboard shortcuts overlay renders
/// [section], and the user docs (#486) are checked against it. Change it in the
/// same commit as the handler.
abstract final class PianoRollShortcutHints {
  static const String _roll = 'piano roll focused';

  static const ShortcutHintSection section = ShortcutHintSection(
    title: 'MIDI',
    hints: [
      ShortcutHint(
        keys: ['Up', 'Down'],
        action: 'Move the caret one pitch',
        note: _roll,
      ),
      ShortcutHint(
        keys: ['Left', 'Right'],
        action: 'Move the caret one snap step',
        note: _roll,
      ),
      ShortcutHint(
        keys: ['Enter'],
        action: 'Drop a note at the caret',
        note: _roll,
      ),
      ShortcutHint(
        keys: ['Delete', 'Backspace'],
        action: 'Delete the selected notes',
        note: _roll,
      ),
      ShortcutHint(
        keys: ['Esc'],
        action: 'Clear the caret, then the selection',
        note: _roll,
      ),
      ShortcutHint(
        keys: ['Ctrl+=', 'Ctrl+-'],
        action: 'Zoom in / out horizontally',
        note: _roll,
      ),
      ShortcutHint(keys: ['Ctrl+wheel'], action: 'Zoom horizontally'),
      ShortcutHint(keys: ['Ctrl+Shift+wheel'], action: 'Zoom vertically'),
      ShortcutHint(keys: ['Middle-drag'], action: 'Pan the zoomed roll'),
    ],
  );
}
