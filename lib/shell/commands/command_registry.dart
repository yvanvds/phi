import 'package:flutter/widgets.dart';

import 'phi_command.dart';

/// The shell's registry of invocable [PhiCommand]s (design
/// `docs/design/shell-layout.md` §4). The workstation seeds it (project ops,
/// settings, surface summon, transport) and surfaces register their own as they
/// grow; the command palette reads it and it is the home of the default shortcut
/// map (issue #255 folds the app's bindings in through [shortcutBindings]).
///
/// A [ChangeNotifier] so an open palette can rebuild as commands come and go, and
/// so recording a recently-used command (which floats it to the top next time)
/// notifies too.
class CommandRegistry extends ChangeNotifier {
  final List<PhiCommand> _commands = [];
  final Map<String, PhiCommand> _byId = {};

  /// Command ids most-recently invoked first — the palette's "recently-used
  /// first" order (design §4).
  final List<String> _recents = [];

  /// Every registered command, in registration order.
  List<PhiCommand> get commands => List.unmodifiable(_commands);

  /// Only the commands enabled right now — what the palette offers.
  List<PhiCommand> get enabledCommands =>
      _commands.where((c) => c.isEnabled).toList(growable: false);

  /// Recently-invoked command ids, newest first.
  List<String> get recentIds => List.unmodifiable(_recents);

  /// The command with [id], or `null` when none is registered.
  PhiCommand? byId(String id) => _byId[id];

  /// Registers [command]. Throws if its id is already taken — ids are the stable
  /// handle the shortcut map and (later) rebinding UI address.
  void register(PhiCommand command) {
    _add(command);
    notifyListeners();
  }

  /// Registers every command in [commands] as one batch, notifying once.
  void registerAll(Iterable<PhiCommand> commands) {
    var added = false;
    for (final command in commands) {
      _add(command);
      added = true;
    }
    if (added) notifyListeners();
  }

  void _add(PhiCommand command) {
    if (_byId.containsKey(command.id)) {
      throw ArgumentError('Duplicate command id: ${command.id}');
    }
    _byId[command.id] = command;
    _commands.add(command);
  }

  /// Removes the command with [id] (e.g. a surface unregistering as it closes).
  /// A no-op when nothing is registered under [id].
  void unregister(String id) {
    final removed = _byId.remove(id);
    if (removed == null) return;
    _commands.remove(removed);
    _recents.remove(id);
    notifyListeners();
  }

  /// Runs the command with [id] if it exists and is enabled, recording it as the
  /// most-recently-used. Returns whether it ran; a disabled or unknown id is a
  /// silent no-op. This is the one path the palette (and a bound shortcut) run,
  /// so recents tracking is uniform.
  bool invoke(String id) {
    final command = _byId[id];
    if (command == null || !command.isEnabled) return false;
    _recents
      ..remove(id)
      ..insert(0, id);
    notifyListeners();
    command.invoke();
    return true;
  }

  /// The default shortcut map for the shell to bind (issue #255): each command
  /// that advertises a [PhiCommand.shortcut] maps every one of its
  /// [CommandShortcut.activators] (the primary chord plus any aliases) to an
  /// invocation that goes through [invoke] — so a keystroke and the palette
  /// share the same code path and recents bookkeeping. This registry is the
  /// single source of truth for the app's default shortcut map (design
  /// `docs/design/shell-layout.md` §4).
  ///
  /// **Debug conflict assertion:** two commands claiming the same chord is a
  /// programming error — the map would silently drop one binding. In debug
  /// builds this throws so the clash fails fast in development; release builds
  /// skip the check (the assert body does not run) and last-registered wins.
  Map<ShortcutActivator, VoidCallback> shortcutBindings() {
    final bindings = <ShortcutActivator, VoidCallback>{};
    // Keyed by a value-comparable chord tuple, not the activator itself:
    // `SingleActivator` has only identity equality, so two distinct instances
    // of the same chord would never collide as map keys. `CallbackShortcuts`
    // matches by `accepts()` regardless, so the returned map's identity keys are
    // fine there — the tuple only guards conflict detection.
    final claimedBy = <(int, bool, bool, bool, bool), String>{};
    for (final command in _commands) {
      final shortcut = command.shortcut;
      if (shortcut == null) continue;
      for (final activator in shortcut.activators) {
        final chord = (
          activator.trigger.keyId,
          activator.control,
          activator.shift,
          activator.alt,
          activator.meta,
        );
        assert(() {
          final owner = claimedBy[chord];
          if (owner != null) {
            throw FlutterError(
              'Shortcut conflict: commands "$owner" and "${command.id}" both '
              'bind ${_describe(activator)}. Each chord must map to exactly one '
              'command (issue #255).',
            );
          }
          claimedBy[chord] = command.id;
          return true;
        }());
        bindings[activator] = () => invoke(command.id);
      }
    }
    return bindings;
  }

  /// Human-readable chord for a conflict message, e.g. `Ctrl+Shift+P`.
  static String _describe(SingleActivator a) => <String>[
    if (a.control) 'Ctrl',
    if (a.shift) 'Shift',
    if (a.alt) 'Alt',
    if (a.meta) 'Meta',
    a.trigger.keyLabel.isEmpty
        ? (a.trigger.debugName ?? '?')
        : a.trigger.keyLabel,
  ].join('+');
}
