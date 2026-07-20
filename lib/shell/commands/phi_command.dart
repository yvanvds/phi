import 'package:flutter/foundation.dart';

import 'command_shortcut.dart';

/// A single invocable action in the shell's `CommandRegistry` (design
/// `docs/design/shell-layout.md` §4).
///
/// The palette is a *launcher*, never a second implementation: [invoke] routes
/// through the very same code path the command's menu / button / rail
/// equivalent runs. A command carries an optional [shortcut] (shown per row and
/// bindable by the shell — issue #255) and an optional enabled-predicate; the
/// palette hides disabled commands.
@immutable
class PhiCommand {
  const PhiCommand({
    required this.id,
    required this.title,
    required this.category,
    required this.invoke,
    this.shortcut,
    bool Function()? isEnabled,
  }) : _isEnabled = isEnabled;

  /// Stable identity, e.g. `project.save`, `surface.mix`, `transport.play`.
  final String id;

  /// Human-readable action name shown in the palette and fuzzy-matched first.
  final String title;

  /// Grouping label (e.g. `Project`, `Transport`, `Surface`), also matched.
  final String category;

  /// The action — the same callback the menu / button equivalent runs.
  final VoidCallback invoke;

  /// Optional key chord, shown on the row and bindable by the shell.
  final CommandShortcut? shortcut;

  final bool Function()? _isEnabled;

  /// Whether the command can run right now. Commands with no predicate are
  /// always enabled; the palette never shows a disabled command (design §4).
  bool get isEnabled => _isEnabled?.call() ?? true;
}
