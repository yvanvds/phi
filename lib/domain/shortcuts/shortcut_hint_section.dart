import 'shortcut_hint.dart';

/// A titled group of [ShortcutHint]s — one per surface (`Patcher`, `MIDI`, …)
/// plus the shell's `Global` and `Lists & dialogs` groups (issue #487).
///
/// Pure data like [ShortcutHint], so the overlay and the user docs (#486) read
/// the same tables.
class ShortcutHintSection {
  const ShortcutHintSection({required this.title, required this.hints});

  /// Section heading, e.g. `Patcher`.
  final String title;

  /// The section's hints, in display order.
  final List<ShortcutHint> hints;
}
