// ignore_for_file: invalid_use_of_internal_member, implementation_imports
import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
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
  SubpatchWindowEntry? entryFor(PatcherController editor, PatchNodeId? box) {
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
  /// A null [box] shows the whole of [editor]'s patch: the definition of an
  /// abstraction (issue #553). [owner] is the patch in the main window when that
  /// is not [editor]'s, and [root] what the window's path starts with then.
  ///
  /// Needs Flutter's windowing feature (`flutter config --enable-windowing`,
  /// on the pinned master, #478); without it nothing opens and the reason is
  /// logged rather than thrown into a menu callback.
  void open(
    PatcherController editor,
    PatchNodeId? box, {
    PatcherController? owner,
    String? root,
  }) {
    if (_disposed || (box != null && !editor.isSubpatch(box))) return;
    if (!isWindowingEnabled) {
      debugPrint('subpatch window: windowing is not enabled in this build');
      return;
    }
    final existing = entryFor(editor, box);
    if (existing != null) {
      existing.window.activate();
      return;
    }
    final title = editor.scopeTitle(box, root: root);
    final window = _nativeWindow(title);
    final entry = SubpatchWindowEntry(
      editor: editor,
      box: box,
      window: window,
      owner: owner,
      root: root,
    )..title = title;
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
  ///
  /// The native window is destroyed **last**: first whatever holds the
  /// keyboard in it lets go, then the frame takes its widgets out of the tree,
  /// then the platform is given the chance to handle what they sent on the way
  /// out ([_retire]). A text field in the window sends its text input calls
  /// for that window's view, and the Windows embedder fails every one whose
  /// view is already gone (`Text input is not available because view with
  /// view_id=N cannot be found`) — which is what a window destroyed under a
  /// half-typed object box used to cause.
  void close(SubpatchWindowEntry entry) {
    if (!_entries.remove(entry)) return;
    _unwatchIfIdle(entry.editor);
    _releaseKeyboard(entry.window);
    if (!_disposed) notifyListeners();
    unawaited(_retire(entry.window));
  }

  /// Unfocus whatever holds the keyboard inside [window], so a text field
  /// there closes its text input connection while its view still exists.
  static void _releaseKeyboard(WindowController window) {
    final focus = FocusManager.instance.primaryFocus;
    final context = focus?.context;
    if (focus == null || context == null || !context.mounted) return;
    if (View.maybeOf(context) == window.rootView) focus.unfocus();
  }

  /// A method no text input plugin implements: the cheapest round trip on the
  /// text input channel, answered (with "not implemented") only once the
  /// platform has handled everything sent on that channel before it.
  static const String _textInputBarrier = 'TextInput.phiSubpatchWindowBarrier';

  /// Destroy [window] once nothing of it can still be in flight: after the
  /// frame that unmounts its widgets (their text input connections close
  /// there), and after a round trip on the text input channel, which the
  /// platform answers in order — so every call those fields made on the way
  /// out has met a live view. Destroying is a synchronous FFI call, while the
  /// text input calls are platform messages handled on a later turn of the
  /// platform loop; without this wait the destroy overtakes them.
  static Future<void> _retire(WindowController window) async {
    await SchedulerBinding.instance.endOfFrame;
    try {
      await SystemChannels.textInput.invokeMethod<void>(_textInputBarrier);
    } on MissingPluginException {
      // The expected answer: no plugin knows the barrier.
    } on PlatformException {
      // Answered all the same; only the ordering matters.
    }
    if (!window.isDestroyed) window.destroy();
  }

  /// Close every window that does not belong to [editor] — the patch they
  /// were opened from is no longer the open one (a switch, a tutorial, a
  /// project swap), and a subpatch never outlives its patch on screen.
  void closeAllExcept(PatcherController? editor) {
    for (final e in _entries.toList()) {
      if (!identical(e.owner, editor)) close(e);
    }
  }

  /// Close every window whose editor [isLive] no longer vouches for: the patch
  /// it showed was renamed, deleted or swapped away (issue #553), so that editor
  /// is gone even though the patch in the main window is still open.
  void closeUnless(bool Function(PatcherController editor) isLive) {
    for (final e in _entries.toList()) {
      if (!isLive(e.editor)) close(e);
    }
  }

  /// Close every window.
  void closeAll() => closeAllExcept(null);

  /// The window's close button: close it the orderly way ([close]) rather
  /// than letting the platform destroy it under a field that holds the
  /// keyboard.
  void _closeRequested(WindowController window) {
    for (final e in _entries) {
      if (identical(e.window, window)) return close(e);
    }
    unawaited(_retire(window));
  }

  /// The native window was taken down from outside — the platform did it.
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
      final box = e.box;
      if (box != null && !e.editor.isSubpatch(box)) {
        close(e);
        continue;
      }
      final title = e.editor.scopeTitle(box, root: e.root);
      if (title != e.title) {
        e.title = title;
        e.window.setTitle(title);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final e in _entries.toList()) {
      _entries.remove(e);
      // The windows' widgets are leaving the tree with the surface; destroy
      // each native window only after they have (see [close]).
      _releaseKeyboard(e.window);
      unawaited(_retire(e.window));
    }
    for (final MapEntry(key: editor, value: listener) in _watched.entries) {
      editor.graph.removeListener(listener);
    }
    _watched.clear();
    super.dispose();
  }
}

/// Routes a subpatch window's close button through the registry, and hears
/// the platform taking a window down, so the registry lets go of it.
class _ClosedByPlatform with WindowControllerDelegate {
  _ClosedByPlatform(this._windows);

  final SubpatchWindows _windows;

  /// The window this delegate was handed to, set right after it is created.
  WindowController? window;

  @override
  void onWindowCloseRequested(WindowController controller) =>
      _windows._closeRequested(controller);

  @override
  void onWindowDestroyed() {
    final w = window;
    if (w != null) _windows._windowDestroyed(w);
    super.onWindowDestroyed();
  }
}
