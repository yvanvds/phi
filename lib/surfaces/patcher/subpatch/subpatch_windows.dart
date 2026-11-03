// ignore_for_file: invalid_use_of_internal_member, implementation_imports
import 'dart:async';

import 'package:flutter/src/foundation/_features.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/widgets.dart';

import '../../../domain/patcher/patch_node_id.dart';
import '../../../engine/state/patcher_controller.dart';
import 'subpatch_window_entry.dart';

/// The subpatch windows open over the patcher surface (issue #481) — Max's
/// "open the `p` box in its own window".
///
/// Each one shows one subpatch box of one editor in a **native window** of its
/// own (Flutter's experimental windowing API, which is why Phi builds on a
/// pinned Flutter master, #478). The window is plain Flutter UI in the main
/// isolate: its canvas drives the very [PatcherController] the main window
/// does, so an edit in either lands on the same graph and the same undo
/// journal.
///
/// The rules the issue sets:
/// - opening a subpatch that is already open **focuses** its window;
/// - a window whose box is gone (deleted, or its whole patch closed) closes;
/// - the app or the surface going away closes them all ([dispose]).
///
/// [SubpatchWindowsHost] renders the windows; this only holds and prunes them.
class SubpatchWindows extends ChangeNotifier {
  /// The size a subpatch window opens at.
  static const Size defaultSize = Size(960, 640);

  final List<SubpatchWindowEntry> _entries = [];

  /// The editors whose graphs this is listening to, with the listener.
  final Map<PatcherController, VoidCallback> _watched = {};

  bool _pruneScheduled = false;
  bool _disposed = false;

  /// Every open window, oldest first.
  List<SubpatchWindowEntry> get entries => List.unmodifiable(_entries);

  /// The window showing [box] of [editor], or null when it is not open.
  SubpatchWindowEntry? entryFor(PatcherController editor, PatchNodeId box) {
    for (final e in _entries) {
      if (identical(e.editor, editor) && e.box == box) return e;
    }
    return null;
  }

  /// Whether any window of [editor] is open — the live-value poll keeps running
  /// for it even while the patcher tab itself is in the background.
  bool hasWindowsFor(PatcherController? editor) =>
      _entries.any((e) => identical(e.editor, editor));

  /// Open [box] of [editor] in its own window, or bring its window to the front
  /// when it is already open. A no-op for anything that is not a subpatch box.
  ///
  /// Needs Flutter's windowing feature (`flutter config --enable-windowing`,
  /// on the pinned master, #478); without it nothing opens and the reason is
  /// logged rather than thrown into a menu callback.
  void open(PatcherController editor, PatchNodeId box) {
    if (_disposed || !editor.isSubpatch(box)) return;
    if (!isWindowingEnabled) {
      debugPrint('subpatch window: windowing is not enabled in this build');
      return;
    }
    final existing = entryFor(editor, box);
    if (existing != null) {
      existing.window.activate();
      return;
    }
    final title = _titleFor(editor, box);
    final window = _nativeWindow(title);
    final entry = SubpatchWindowEntry(editor: editor, box: box, window: window)
      ..title = title;
    _entries.add(entry);
    _watch(editor);
    notifyListeners();
  }

  WindowController _nativeWindow(String title) {
    final delegate = _ClosedByPlatform(this);
    return delegate.window = WindowController(
      size: defaultSize,
      title: title,
      delegate: delegate,
    );
  }

  /// Close one window.
  void close(SubpatchWindowEntry entry) {
    if (!_entries.remove(entry)) return;
    _unwatchIfIdle(entry.editor);
    notifyListeners();
    entry.window.destroy();
  }

  /// Close every window that does not belong to [editor] — the patch they
  /// were opened from is no longer the open one (a switch, a tutorial, a
  /// project swap), and a subpatch never outlives its patch on screen.
  void closeAllExcept(PatcherController? editor) {
    for (final e in _entries.toList()) {
      if (!identical(e.editor, editor)) close(e);
    }
  }

  /// Close every window.
  void closeAll() => closeAllExcept(null);

  /// The native window was closed from outside — its close button, or the
  /// platform taking it down.
  void _windowDestroyed(WindowController window) {
    for (final e in _entries.toList()) {
      if (!identical(e.window, window)) continue;
      _entries.remove(e);
      _unwatchIfIdle(e.editor);
      if (!_disposed) notifyListeners();
    }
  }

  void _watch(PatcherController editor) {
    if (_watched.containsKey(editor)) return;
    void listener() => _schedulePrune();
    _watched[editor] = listener;
    editor.graph.addListener(listener);
  }

  void _unwatchIfIdle(PatcherController editor) {
    if (hasWindowsFor(editor)) return;
    final listener = _watched.remove(editor);
    if (listener != null) editor.graph.removeListener(listener);
  }

  /// A graph change may have deleted a box (or renamed one): settle it once
  /// the change is done, outside whatever notified — a window must not leave
  /// the tree in the middle of a build.
  void _schedulePrune() {
    if (_pruneScheduled) return;
    _pruneScheduled = true;
    scheduleMicrotask(() {
      _pruneScheduled = false;
      if (!_disposed) prune();
    });
  }

  /// Close the windows whose box is gone and re-title the ones whose path
  /// changed. Runs by itself after every graph change; public so a test can
  /// settle it synchronously.
  void prune() {
    for (final e in _entries.toList()) {
      if (!e.editor.isSubpatch(e.box)) {
        close(e);
        continue;
      }
      final title = _titleFor(e.editor, e.box);
      if (title != e.title) {
        e.title = title;
        e.window.setTitle(title);
      }
    }
  }

  /// The window title: the subpatch's path from the top of its patch.
  static String _titleFor(PatcherController editor, PatchNodeId box) =>
      editor.scopeTitle(box);

  @override
  void dispose() {
    _disposed = true;
    for (final e in _entries.toList()) {
      _entries.remove(e);
      e.window.destroy();
    }
    for (final MapEntry(key: editor, value: listener) in _watched.entries) {
      editor.graph.removeListener(listener);
    }
    _watched.clear();
    super.dispose();
  }
}

/// Hears a subpatch window being taken down by the platform (its close
/// button) so the registry lets go of it.
class _ClosedByPlatform with WindowControllerDelegate {
  _ClosedByPlatform(this._windows);

  final SubpatchWindows _windows;

  /// The window this delegate was handed to, set right after it is created.
  WindowController? window;

  @override
  void onWindowDestroyed() {
    final w = window;
    if (w != null) _windows._windowDestroyed(w);
    super.onWindowDestroyed();
  }
}
