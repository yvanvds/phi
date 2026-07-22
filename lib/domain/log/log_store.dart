import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'log_entry.dart';

/// The in-memory unified log: a fixed-capacity ring buffer of [LogEntry]s that
/// the panel (issue #270) watches (design `docs/design/diagnostics.md` §2).
///
/// A [ChangeNotifier] like the other domain stores, so the panel rebuilds on
/// every change. When the buffer is full the oldest entry is dropped — a live
/// set can run for hours without the log growing without bound; the *file*
/// (see `SessionLog`) keeps the full history for the morning after.
class LogStore extends ChangeNotifier {
  /// Creates a store holding at most [capacity] entries (default ~2000, the
  /// design's ring-buffer size).
  LogStore({this.capacity = defaultCapacity})
    : assert(capacity > 0, 'capacity must be positive');

  /// The design's default ring-buffer size.
  static const int defaultCapacity = 2000;

  /// The most entries the store holds before dropping the oldest.
  final int capacity;

  final ListQueue<LogEntry> _entries = ListQueue<LogEntry>();

  /// The buffered entries, oldest first — a read-only snapshot.
  List<LogEntry> get entries => List<LogEntry>.unmodifiable(_entries);

  /// How many entries are currently buffered.
  int get length => _entries.length;

  /// Whether the buffer holds no entries.
  bool get isEmpty => _entries.isEmpty;

  /// Appends [entry], dropping the oldest entry if the buffer is at [capacity],
  /// then notifies listeners.
  void add(LogEntry entry) {
    _entries.addLast(entry);
    if (_entries.length > capacity) _entries.removeFirst();
    notifyListeners();
  }

  /// Drops every buffered entry and notifies listeners. Does nothing (and does
  /// not notify) when already empty.
  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }
}
