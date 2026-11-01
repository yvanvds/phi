/// One discoverable shortcut or gesture, as the keyboard shortcuts overlay
/// shows it and the user docs list it (issue #487).
///
/// Pure data — no Flutter, no FFI — so a surface can declare its local
/// shortcuts next to the `onKeyEvent` handler that implements them, the shell
/// can render them, and a plain Dart test or doc generator can enumerate them.
///
/// [keys] holds every way to trigger the action, each already in display form
/// (`Ctrl+E`, `Shift+Arrows`, `Double-click empty canvas`); the first is the
/// primary one. [note] is the optional mode caveat, e.g. `edit mode only`.
class ShortcutHint {
  const ShortcutHint({required this.keys, required this.action, this.note});

  /// The chords or gestures that trigger [action], primary first.
  final List<String> keys;

  /// What the shortcut does, e.g. `Toggle edit ↔ run mode`.
  final String action;

  /// When the shortcut applies, if not always — `edit mode only`,
  /// `in the object box`, `unavailable while a tutorial is open`.
  final String? note;

  @override
  String toString() =>
      'ShortcutHint(${keys.join(' / ')}: $action'
      '${note == null ? '' : ' — $note'})';
}
