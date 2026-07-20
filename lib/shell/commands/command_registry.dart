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
  /// that advertises a [PhiCommand.shortcut] maps its activator to an invocation
  /// that goes through [invoke] — so a keystroke and the palette share the same
  /// code path and recents bookkeeping.
  Map<ShortcutActivator, VoidCallback> shortcutBindings() {
    final bindings = <ShortcutActivator, VoidCallback>{};
    for (final command in _commands) {
      final shortcut = command.shortcut;
      if (shortcut != null) {
        bindings[shortcut.activator] = () => invoke(command.id);
      }
    }
    return bindings;
  }
}
