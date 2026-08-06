import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A key chord a [PhiCommand] can advertise (design
/// `docs/design/shell-layout.md` §4) — both the [SingleActivator] the shell
/// binds it to and the human-readable [label] the palette shows on the command's
/// row.
///
/// Lives in the shell (not `lib/domain/`) because it wraps Flutter's
/// [LogicalKeyboardKey] / [SingleActivator]; the command registry is workstation
/// chrome. Issue #255 folds the app's default shortcut map in through the
/// registry, so this pairs a bindable activator with a display label from the
/// start.
@immutable
class CommandShortcut {
  const CommandShortcut(
    this.trigger, {
    this.control = false,
    this.shift = false,
    this.alt = false,
    this._triggerLabel,
    this.aliases = const [],
  });

  /// The primary key, e.g. [LogicalKeyboardKey.keyP].
  final LogicalKeyboardKey trigger;
  final bool control;
  final bool shift;
  final bool alt;

  /// Optional display override for the trigger (e.g. `F1`), used when the key's
  /// own [LogicalKeyboardKey.keyLabel] is not what we want on screen.
  final String? _triggerLabel;

  /// Extra chords that also fire the command but are not shown on the palette
  /// row — the primary [activator] is the one the row advertises. Lets a single
  /// command own every chord that reaches it (issue #255's "one table owns
  /// them"): e.g. redo answers to both `Ctrl+Shift+Z` and the legacy `Ctrl+Y`,
  /// and the palette opens on `Ctrl+Shift+P` and `F1`.
  final List<SingleActivator> aliases;

  /// The activator the shell binds this chord to (issue #255 folds the default
  /// map in through the registry).
  SingleActivator get activator =>
      SingleActivator(trigger, control: control, shift: shift, alt: alt);

  /// Every activator that must fire the command — the primary [activator]
  /// followed by any [aliases]. The shell binds them all; the conflict
  /// assertion checks them all.
  List<SingleActivator> get activators => [activator, ...aliases];

  /// The chord rendered for a palette row, e.g. `Ctrl+Shift+P`.
  String get label {
    return <String>[
      if (control) 'Ctrl',
      if (shift) 'Shift',
      if (alt) 'Alt',
      _triggerLabel ?? _labelFor(trigger),
    ].join('+');
  }

  static String _labelFor(LogicalKeyboardKey key) {
    // Keyed by `keyId` because `LogicalKeyboardKey` overrides `==`, so it can't
    // be a (const) map key itself.
    final named = _namedTriggers[key.keyId];
    if (named != null) return named;
    final keyLabel = key.keyLabel;
    return keyLabel.isEmpty ? (key.debugName ?? '?') : keyLabel;
  }

  /// Display names for triggers whose [LogicalKeyboardKey.keyLabel] is empty or
  /// unfriendly (control keys carry no printable label).
  static final Map<int, String> _namedTriggers = {
    LogicalKeyboardKey.f1.keyId: 'F1',
    LogicalKeyboardKey.f2.keyId: 'F2',
    LogicalKeyboardKey.tab.keyId: 'Tab',
    LogicalKeyboardKey.enter.keyId: 'Enter',
    LogicalKeyboardKey.escape.keyId: 'Esc',
    LogicalKeyboardKey.space.keyId: 'Space',
    LogicalKeyboardKey.arrowUp.keyId: 'Up',
    LogicalKeyboardKey.arrowDown.keyId: 'Down',
    LogicalKeyboardKey.arrowLeft.keyId: 'Left',
    LogicalKeyboardKey.arrowRight.keyId: 'Right',
  };

  @override
  bool operator ==(Object other) =>
      other is CommandShortcut &&
      other.trigger == trigger &&
      other.control == control &&
      other.shift == shift &&
      other.alt == alt &&
      other._triggerLabel == _triggerLabel;

  @override
  int get hashCode => Object.hash(trigger, control, shift, alt, _triggerLabel);
}
