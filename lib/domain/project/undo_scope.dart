import 'package:flutter/foundation.dart';

import 'project_command.dart';

/// Whether the most recent [UndoScope] mutation applied a command forward
/// ([applied] — a `run` or `redo`) or applied its inverse ([reverted] — an
/// `undo`). A listener that mirrors per-command UI state (the MIDI editor
/// reselecting the notes an edit just touched) reads it after a notification.
enum UndoEvent { applied, reverted }

/// A single surface's undo/redo stack — the concrete "stack" behind
/// *undo follows focus* (design `docs/design/project-registry.md` §6).
///
/// Holds [ProjectCommand]s: [run] applies a fresh command and clears the redo
/// stack; [undo] applies the top command's inverse and moves it to the redo
/// stack; [redo] re-applies it. An undo therefore *applies the inverse command*
/// — the same mechanism as any other apply — so a later journal (#122) can
/// record it as one more linear entry even though undo is scoped per surface.
///
/// **Gesture coalescing (a convention, not machinery).** Continuous
/// interactions — fader drags, note drags, live param-editor keystrokes —
/// mutate transient widget state freely and call [run] exactly once, on gesture
/// end. The piano roll is the prototype: a drag previews locally and commits a
/// single command on release, so undo works in human-sized steps and the
/// journal never bloats.
///
/// A [ChangeNotifier]: it notifies on every [run]/[undo]/[redo]/[clear] so the
/// owning surface can repaint and the [UndoScopes] router (or a menu) can
/// re-enable items. After a notification [lastCommand] and [lastEvent] describe
/// what just happened.
class UndoScope extends ChangeNotifier {
  UndoScope({required this.id, String? label}) : label = label ?? id;

  /// Stable key the [UndoScopes] router registers and focuses this scope by —
  /// the owning surface's identity (the MIDI surface is `'midi'`, #119).
  final String id;

  /// Human-readable name for a menu or status line ("MIDI editor").
  final String label;

  final List<ProjectCommand> _undo = [];
  final List<ProjectCommand> _redo = [];
  ProjectCommand? _lastCommand;
  UndoEvent? _lastEvent;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// The command touched by the most recent mutation, or `null` after [clear].
  ProjectCommand? get lastCommand => _lastCommand;

  /// Whether the most recent mutation applied or reverted [lastCommand], or
  /// `null` after [clear].
  UndoEvent? get lastEvent => _lastEvent;

  /// Applies [command], pushing it onto the undo stack and dropping any
  /// redoable history — a fresh edit forks the timeline.
  void run(ProjectCommand command) {
    command.apply();
    _undo.add(command);
    _redo.clear();
    _emit(command, UndoEvent.applied);
  }

  /// Reverts the top command (applying its inverse) and moves it to the redo
  /// stack. A no-op — with no notification — when [canUndo] is false.
  void undo() {
    if (_undo.isEmpty) return;
    final command = _undo.removeLast();
    command.revert();
    _redo.add(command);
    _emit(command, UndoEvent.reverted);
  }

  /// Re-applies the last undone command. A no-op — with no notification — when
  /// [canRedo] is false.
  void redo() {
    if (_redo.isEmpty) return;
    final command = _redo.removeLast();
    command.apply();
    _undo.add(command);
    _emit(command, UndoEvent.applied);
  }

  /// Drops all history. Used when the underlying state is rebuilt out from
  /// under the stack (e.g. a clip replaced by a file import) so the captured
  /// commands — which index into state that no longer exists — can't be
  /// replayed.
  void clear() {
    _undo.clear();
    _redo.clear();
    _lastCommand = null;
    _lastEvent = null;
    notifyListeners();
  }

  void _emit(ProjectCommand command, UndoEvent event) {
    _lastCommand = command;
    _lastEvent = event;
    notifyListeners();
  }
}
