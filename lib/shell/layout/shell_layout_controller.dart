import 'package:flutter/foundation.dart';

import '../../domain/shell_layout/drop_edge.dart';
import '../../domain/shell_layout/layout_node.dart';
import '../../domain/shell_layout/shell_layout.dart';

/// Shell-side owner of the workspace [ShellLayout] (design
/// `docs/design/shell-layout.md` §2). Holds the split tree plus the **active
/// pane** — the pane a rail summon opens a closed surface into — and exposes the
/// mutations the workstation and (later) the tab/split interactions drive, each
/// applied through the pure-domain layout so the invariants are never re-derived
/// here.
///
/// The controller is deliberately thin: every structural rule lives in
/// [ShellLayout]. It adds only the *stateful* bits the domain value type can't
/// carry — which pane is active and the change notification the UI listens to.
class ShellLayoutController extends ChangeNotifier {
  /// Builds a controller around an initial [layout] (defaulting to the seed —
  /// one pane, Mix open — so the app boots behaviour-neutral) with its active
  /// pane set to [activePaneId] or, failing that, the first pane.
  ShellLayoutController({ShellLayout? layout, String? activePaneId})
    : _layout = layout ?? ShellLayout.seed() {
    _activePaneId =
        (activePaneId != null && _layout.paneById(activePaneId) != null)
        ? activePaneId
        : _layout.panes.first.id;
  }

  ShellLayout _layout;
  late String _activePaneId;

  /// The current split tree + tab stacks.
  ShellLayout get layout => _layout;

  /// The id of the pane a closed surface is summoned into (design §2 — "opens it
  /// in the active pane if closed"). Always a live pane.
  String get activePaneId => _activePaneId;

  /// The active pane — the stored one, or the first pane if that id has gone
  /// stale (never null; there is always at least one pane).
  LayoutPane get activePane =>
      _layout.paneById(_activePaneId) ?? _layout.panes.first;

  /// The focused surface — the active tab of the active pane, or null when that
  /// pane is empty. This is what the rail highlights.
  String? get focusedSurface => activePane.active;

  /// Rail summon (design §2, §3): focus [surfaceId] wherever it lives — making
  /// it its pane's active tab and that pane the active one — or, when it is
  /// closed, open it in the active pane and focus it there.
  void summon(String surfaceId) {
    final homePaneId = _layout.paneIdOf(surfaceId);
    if (homePaneId != null) {
      _apply(_layout.activate(surfaceId), activePaneId: homePaneId);
    } else {
      _apply(
        _layout.moveSurface(surfaceId, _activePaneId),
        activePaneId: _activePaneId,
      );
    }
  }

  /// Marks [paneId] the active pane (a click into a pane, later). No layout
  /// change — just the summon target. Unknown ids are ignored.
  void setActivePane(String paneId) {
    if (_layout.paneById(paneId) == null || paneId == _activePaneId) return;
    _activePaneId = paneId;
    notifyListeners();
  }

  /// Makes [surfaceId] the active tab of its pane and that pane the active pane
  /// (selecting a tab within a stack). A no-op when the surface is closed.
  void activate(String surfaceId) {
    final homePaneId = _layout.paneIdOf(surfaceId);
    if (homePaneId == null) return;
    _apply(_layout.activate(surfaceId), activePaneId: homePaneId);
  }

  /// Splits [targetPaneId] by dropping [surfaceId] on one of its [edge]s, then
  /// makes the surface's new pane the active one (design §2 — edge drops). The
  /// interactive drag lands in a later slice; this is the operation behind it.
  void split(String targetPaneId, String surfaceId, DropEdge edge) {
    final next = _layout.split(targetPaneId, surfaceId, edge);
    // The split placed the surface in a fresh pane; make that the active one.
    _apply(next, activePaneId: next.paneIdOf(surfaceId) ?? _activePaneId);
  }

  /// Moves [surfaceId] into [toPaneId] (a cross-pane drag / join) and focuses it
  /// there.
  void moveSurface(String surfaceId, String toPaneId, {int? atIndex}) {
    final next = _layout.moveSurface(surfaceId, toPaneId, atIndex: atIndex);
    _apply(next, activePaneId: next.paneIdOf(surfaceId) ?? _activePaneId);
  }

  /// Closes [surfaceId], returning it to the summonable "closed" set (design §2).
  void close(String surfaceId) => _apply(_layout.close(surfaceId));

  /// Resizes the split [splitId] to [fractions] (splitter drag, later).
  void resize(String splitId, List<double> fractions) =>
      _apply(_layout.resize(splitId, fractions));

  /// Replaces the whole layout (e.g. restored from a manifest) and repoints the
  /// active pane, notifying once.
  void replaceLayout(ShellLayout layout, {String? activePaneId}) {
    _layout = layout;
    _activePaneId =
        (activePaneId != null && layout.paneById(activePaneId) != null)
        ? activePaneId
        : layout.panes.first.id;
    notifyListeners();
  }

  /// Commits [next], repairs the active-pane id if it went stale, and notifies —
  /// but only when something actually changed (so an idempotent op is silent).
  void _apply(ShellLayout next, {String? activePaneId}) {
    final nextActive =
        (activePaneId != null && next.paneById(activePaneId) != null)
        ? activePaneId
        : (next.paneById(_activePaneId)?.id ?? next.panes.first.id);
    if (next == _layout && nextActive == _activePaneId) return;
    _layout = next;
    _activePaneId = nextActive;
    notifyListeners();
  }
}
