import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/log/log_entry.dart';
import '../../domain/log/log_filter.dart';
import '../../domain/log/log_level.dart';
import '../../domain/log/log_source.dart';
import '../../domain/log/log_store.dart';
import '../../domain/log/log_transcript.dart';

/// Writes a block of text to the system clipboard — the seam the copy action
/// goes through so a unit test can capture the text without a platform channel.
typedef ClipboardWriter = Future<void> Function(String text);

/// Drives the bottom-drawer log panel (design `docs/design/diagnostics.md` §4):
/// the open/closed state, the combinable [LogFilter], and the status-bar error
/// badge — the count of error entries recorded *while the drawer was closed*
/// since it was last open.
///
/// A [ChangeNotifier] that watches the shared [LogStore], so both the panel and
/// the status-bar toggle rebuild as entries land. The follow/pause/jump scroll
/// behaviour lives in the panel widget (a scroll concern); everything else — the
/// filter, the badge, and copy — is here and unit-tested against a plain store.
class LogPanelController extends ChangeNotifier {
  /// Watches [store]; copies through [clipboard] (defaulting to the real system
  /// clipboard). A test injects a [clipboard] to capture the copied text.
  LogPanelController({required this.store, ClipboardWriter? clipboard})
    : _clipboard = clipboard ?? _systemClipboard {
    store.addListener(_onStoreChanged);
    _mark = _tailOf(store);
  }

  static Future<void> _systemClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  /// The unified log the panel reads and the badge counts over.
  final LogStore store;

  final ClipboardWriter _clipboard;

  bool _isOpen = false;

  /// Whether the drawer is showing.
  bool get isOpen => _isOpen;

  LogFilter _filter = const LogFilter();

  /// The combinable level / source / search query the list is filtered by.
  LogFilter get filter => _filter;

  int _unseenErrors = 0;

  /// Error-level entries recorded while the drawer was closed, since it was last
  /// open — the count the status-bar toggle badges. Cleared whenever the drawer
  /// opens.
  int get unseenErrorCount => _unseenErrors;

  /// Whether the toggle should show its error badge right now.
  bool get hasUnseenErrors => _unseenErrors > 0;

  /// The last entry accounted for by the badge tally — the marker new entries
  /// are diffed against. `null` before any entry (or after a clear).
  LogEntry? _mark;

  /// The store entries passing the current [filter], oldest-first (the panel
  /// renders them newest-*last* with auto-follow).
  List<LogEntry> get visibleEntries => _filter.apply(store.entries);

  void _onStoreChanged() {
    final entries = store.entries;
    if (entries.isEmpty) {
      _mark = null;
      notifyListeners();
      return;
    }
    // Accrue the badge only while closed: an error seen with the drawer open was
    // already visible, so it must not badge on the next close.
    if (!_isOpen) {
      for (final entry in _entriesAfter(entries, _mark)) {
        if (entry.level == LogLevel.error) _unseenErrors++;
      }
    }
    _mark = entries.last;
    notifyListeners();
  }

  /// The entries appended after [marker] (matched by identity). When [marker] is
  /// null or no longer buffered (evicted from the ring), every current entry is
  /// treated as new — a ring-buffer rollover can only ever *under*-count a badge,
  /// never invent errors.
  static Iterable<LogEntry> _entriesAfter(
    List<LogEntry> entries,
    LogEntry? marker,
  ) {
    if (marker == null) return entries;
    for (var i = entries.length - 1; i >= 0; i--) {
      if (identical(entries[i], marker)) return entries.sublist(i + 1);
    }
    return entries;
  }

  static LogEntry? _tailOf(LogStore store) =>
      store.isEmpty ? null : store.entries.last;

  /// Opens the drawer if closed, closes it if open.
  void toggle() => _isOpen ? close() : open();

  /// Opens the drawer, clearing the error badge (the errors are now visible) and
  /// rebasing the badge marker so a later close starts a fresh tally.
  void open() {
    _isOpen = true;
    _unseenErrors = 0;
    _mark = _tailOf(store);
    notifyListeners();
  }

  /// Opens the drawer filtered to errors — the badge-click behaviour (design §4,
  /// §5): "clicking opens filtered to errors and clears the badge".
  void openFilteredToErrors() {
    _filter = const LogFilter(minLevel: LogLevel.error);
    open();
  }

  /// Closes the drawer and rebases the badge marker, so the error count reflects
  /// only what arrives *after* this close — "since the drawer was last open".
  void close() {
    if (!_isOpen) return;
    _isOpen = false;
    _mark = _tailOf(store);
    notifyListeners();
  }

  /// Sets the minimum level shown (this level and above).
  void setMinLevel(LogLevel level) {
    if (level == _filter.minLevel) return;
    _filter = _filter.withMinLevel(level);
    notifyListeners();
  }

  /// Toggles [source] in or out of the shown set.
  void toggleSource(LogSource source) {
    _filter = _filter.withToggledSource(source);
    notifyListeners();
  }

  /// Sets the case-insensitive text search.
  void setQuery(String query) {
    if (query == _filter.query) return;
    _filter = _filter.withQuery(query);
    notifyListeners();
  }

  /// Resets every filter back to the "show everything" default.
  void clearFilters() {
    if (!_filter.isNarrowing) return;
    _filter = const LogFilter();
    notifyListeners();
  }

  /// Copies the currently visible (filtered) entries to the clipboard as
  /// paste-ready plain text (design §4).
  Future<void> copyVisible() => _clipboard(LogTranscript.of(visibleEntries));

  @override
  void dispose() {
    store.removeListener(_onStoreChanged);
    super.dispose();
  }
}
