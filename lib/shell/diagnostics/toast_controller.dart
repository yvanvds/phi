import 'package:flutter/foundation.dart';

import '../../domain/log/log_level.dart';
import 'toast_message.dart';

/// Holds the transient toasts currently on screen (design
/// `docs/design/diagnostics.md` §3) — a [ChangeNotifier] the overlay watches.
///
/// It is deliberately timer-free: each toast's auto-dismiss lives in the overlay
/// widget's state (tied to the widget lifecycle, cancelled on dispose), which
/// calls [dismiss] when its time is up. [displayDuration] is the config the
/// overlay reads for that timer, so the whole show/dismiss policy stays in one
/// place while the timing plumbing stays out of the pure state.
class ToastController extends ChangeNotifier {
  /// Creates a controller whose toasts each linger for [displayDuration].
  ToastController({this.displayDuration = const Duration(seconds: 4)});

  /// How long each toast stays before the overlay auto-dismisses it.
  final Duration displayDuration;

  final List<ToastMessage> _visible = <ToastMessage>[];
  int _nextId = 0;

  /// The toasts currently on screen, oldest first — a read-only snapshot.
  List<ToastMessage> get visible => List<ToastMessage>.unmodifiable(_visible);

  /// Adds a toast carrying [text] at [level] and notifies listeners.
  void show(String text, LogLevel level) {
    _visible.add(ToastMessage(id: _nextId++, text: text, level: level));
    notifyListeners();
  }

  /// Removes the toast with [id], if present, and notifies. A no-op (no notify)
  /// when it is already gone.
  void dismiss(int id) {
    final before = _visible.length;
    _visible.removeWhere((t) => t.id == id);
    if (_visible.length != before) notifyListeners();
  }
}
