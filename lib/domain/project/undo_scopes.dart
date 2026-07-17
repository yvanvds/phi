import 'package:flutter/foundation.dart';

import 'undo_scope.dart';

/// The app's set of per-surface [UndoScope]s plus the one that currently has
/// focus — the machinery behind *undo follows focus* (design §6).
///
/// Ctrl+Z/Y are routed here by the shell; [undo]/[redo] act on the [focused]
/// scope only, so a piano-roll edit is never yanked out from under a mix tweak
/// five minutes later. Each surface [register]s its scope once; the shell
/// [focus]es the scope matching the active surface. An unfocused or unknown
/// surface leaves [focused] `null`, and undo/redo become no-ops — nothing to
/// yank.
///
/// A [ChangeNotifier]: it notifies when focus changes (or a scope is
/// registered/unregistered) so a menu can show which stack Ctrl+Z would act on.
/// It does **not** forward the focused scope's own notifications — no consumer
/// needs reactive [canUndo] yet; a menu that does can listen to [focused]
/// directly.
class UndoScopes extends ChangeNotifier {
  final Map<String, UndoScope> _scopes = {};
  String? _focusedId;

  /// The registered scopes, in registration order.
  Iterable<UndoScope> get scopes => _scopes.values;

  /// The scope Ctrl+Z/Y currently act on, or `null` when nothing is focused.
  UndoScope? get focused => _focusedId == null ? null : _scopes[_focusedId];

  /// The [focused] scope's id, or `null`.
  String? get focusedId => _focusedId;

  bool get canUndo => focused?.canUndo ?? false;
  bool get canRedo => focused?.canRedo ?? false;

  /// Registers [scope] under its [UndoScope.id]. A second register with the
  /// same id replaces the entry.
  void register(UndoScope scope) {
    _scopes[scope.id] = scope;
    notifyListeners();
  }

  /// Drops the scope registered under [id], clearing focus if it held it.
  void unregister(String id) {
    if (_scopes.remove(id) == null) return;
    if (_focusedId == id) _focusedId = null;
    notifyListeners();
  }

  /// Points undo/redo at the scope registered under [id] — or nothing when
  /// [id] is `null`. Called by the shell as the active surface changes.
  void focus(String? id) {
    if (id == _focusedId) return;
    _focusedId = id;
    notifyListeners();
  }

  /// Undoes one step on the [focused] scope, if any.
  void undo() => focused?.undo();

  /// Redoes one step on the [focused] scope, if any.
  void redo() => focused?.redo();
}
