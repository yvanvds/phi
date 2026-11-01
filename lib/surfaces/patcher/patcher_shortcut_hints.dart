import '../../domain/shortcuts/shortcut_hint.dart';
import '../../domain/shortcuts/shortcut_hint_section.dart';

/// The patcher's surface-local shortcuts and gestures (issue #487), declared
/// next to the handlers that implement them: `PatcherCanvas._onKey` and its
/// pointer routing, the inline object box (`create/patch_inline_object_box.dart`)
/// and the number box (`nodes/number_node_body.dart`).
///
/// FFI-free and Flutter-free on purpose: the shell's keyboard shortcuts overlay
/// renders [section], and the user docs (#486) are checked against it. When a
/// handler gains or loses a key, change this table in the same commit.
abstract final class PatcherShortcutHints {
  static const String _edit = 'edit mode only';
  static const String _box = 'in the object box';

  static const ShortcutHintSection section = ShortcutHintSection(
    title: 'Patcher',
    hints: [
      ShortcutHint(
        keys: ['N', 'Double-click empty canvas'],
        action: 'Insert an object (opens the object box)',
        note: _edit,
      ),
      ShortcutHint(
        keys: ['Ctrl+E'],
        action: 'Toggle edit ↔ run mode',
        note: 'unavailable while a tutorial is open',
      ),
      ShortcutHint(
        keys: ['Double-click an object'],
        action: 'Retype it / edit its arguments in place',
        note: _edit,
      ),
      ShortcutHint(
        keys: ['Drag from the palette'],
        action: 'Create an object at the drop point',
        note: _edit,
      ),
      ShortcutHint(
        keys: ['Delete', 'Backspace'],
        action: 'Delete the selection',
        note: _edit,
      ),
      ShortcutHint(
        keys: ['Ctrl+D'],
        action: 'Duplicate the selection',
        note: _edit,
      ),
      ShortcutHint(
        keys: ['Ctrl+C', 'Ctrl+V'],
        action: 'Copy / paste the selection',
        note: _edit,
      ),
      ShortcutHint(
        keys: ['Ctrl+Z', 'Ctrl+Shift+Z', 'Ctrl+Y'],
        action: 'Undo / redo',
        note: _edit,
      ),
      ShortcutHint(
        keys: ['Arrows', 'Shift+Arrows'],
        action: 'Nudge the selection one grid cell / one major cell',
        note: _edit,
      ),
      ShortcutHint(keys: ['Esc'], action: 'Clear the selection', note: _edit),
      ShortcutHint(
        keys: ['Shift+click', 'Drag on empty canvas'],
        action: 'Extend the selection / marquee select',
        note: _edit,
      ),
      ShortcutHint(keys: ['Space+drag', 'Middle-drag'], action: 'Pan'),
      ShortcutHint(keys: ['Wheel'], action: 'Zoom about the pointer'),
      ShortcutHint(keys: ['Ctrl+0'], action: 'Frame the whole patch'),
      ShortcutHint(
        keys: ['Right-click an object'],
        action: 'Object context menu',
      ),
      ShortcutHint(
        keys: ['Up', 'Down'],
        action: 'Move through the completions',
        note: _box,
      ),
      ShortcutHint(
        keys: ['Tab'],
        action: 'Accept the highlighted completion',
        note: _box,
      ),
      ShortcutHint(keys: ['Enter'], action: 'Create the object', note: _box),
      ShortcutHint(
        keys: ['Shift+Enter'],
        action: 'Line break in a note',
        note: _box,
      ),
      ShortcutHint(keys: ['Esc'], action: 'Dismiss the box', note: _box),
      ShortcutHint(
        keys: ['Esc'],
        action: 'Revert the number being typed',
        note: 'in a number box',
      ),
    ],
  );
}
