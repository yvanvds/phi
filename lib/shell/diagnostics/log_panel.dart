import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_motion.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/log/log_entry.dart';
import 'log_entry_row.dart';
import 'log_filter_bar.dart';
import 'log_panel_controller.dart';

/// The bottom-drawer log panel (design `docs/design/diagnostics.md` §4): the
/// filtered, searchable log with copy, sitting above the status bar.
///
/// Entries render newest-*last* with **auto-follow**: while the view is pinned to
/// the bottom, a new entry scrolls it into view; scrolling up **pauses** follow
/// (a jump-to-newest button appears) until the performer returns to the bottom
/// or taps the button. The filter/search/badge state lives in the
/// [LogPanelController]; the scroll follow state is local widget state.
class LogPanel extends StatefulWidget {
  /// Renders the drawer over [controller].
  const LogPanel({required this.controller, super.key});

  /// The panel controller — the entries, filter, and copy action.
  final LogPanelController controller;

  /// The drawer's fixed height above the status bar (design decision 2: a
  /// glanceable drawer, no layout disturbance).
  static const double height = 260;

  /// Keys tests target the header affordances by.
  static const Key jumpToNewestKey = Key('LogPanel.jumpToNewest');
  static const Key copyKey = Key('LogPanel.copy');
  static const Key clearKey = Key('LogPanel.clearFilters');
  static const Key closeKey = Key('LogPanel.close');

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final ScrollController _scroll = ScrollController();

  /// Whether the list auto-scrolls to the newest entry. Paused when the
  /// performer scrolls up, resumed at the bottom or via jump-to-newest.
  bool _following = true;

  /// True while the pointer is dragging the list — distinguishes a user scroll
  /// (which can pause follow) from our own programmatic jump-to-bottom.
  bool _userDragging = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    // Land pinned to the newest entry on open.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _scroll.dispose();
    super.dispose();
  }

  /// A store change (or filter change) rebuilds the list; when following, keep
  /// the newest entry pinned after the new content lays out.
  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_following) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom({bool animated = false}) {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (animated) {
      _scroll.animateTo(
        max,
        duration: PhiMotion.dur2,
        curve: PhiMotion.easeOut,
      );
    } else {
      _scroll.jumpTo(max);
    }
  }

  void _setFollowing(bool value) {
    if (value == _following) return;
    setState(() => _following = value);
  }

  /// Follow tracks the scroll gesture, not programmatic content growth: only a
  /// user drag away from the bottom pauses it, and a drag that ends at the
  /// bottom resumes it — so a burst of new entries never silently unpins.
  bool _onScrollNotification(ScrollNotification n) {
    if (!_scroll.hasClients) return false;
    final atBottom =
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 8;
    if (n is ScrollStartNotification) {
      _userDragging = n.dragDetails != null;
    } else if (n is ScrollUpdateNotification) {
      if (_userDragging && !atBottom) _setFollowing(false);
    } else if (n is ScrollEndNotification) {
      if (_userDragging) _setFollowing(atBottom);
      _userDragging = false;
    }
    return false;
  }

  void _jumpToNewest() {
    _setFollowing(true);
    _scrollToBottom(animated: true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final entries = controller.visibleEntries;
    return Container(
      height: LogPanel.height,
      decoration: const BoxDecoration(
        color: PhiColors.bg1,
        border: Border(top: BorderSide(color: PhiColors.line1)),
      ),
      child: Column(
        children: [
          _header(controller),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PhiSpacing.s3,
              0,
              PhiSpacing.s3,
              PhiSpacing.s2,
            ),
            child: LogFilterBar(controller: controller),
          ),
          const Divider(height: 1, thickness: 1, color: PhiColors.line1),
          Expanded(child: _list(entries)),
        ],
      ),
    );
  }

  Widget _header(LogPanelController controller) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s3),
      child: Row(
        children: [
          Text('LOG', style: PhiType.caption().copyWith(color: PhiColors.fg1)),
          const SizedBox(width: PhiSpacing.s3),
          Text(
            '${controller.visibleEntries.length}',
            style: PhiType.monoS().copyWith(color: PhiColors.fg3),
          ),
          const Spacer(),
          if (controller.filter.isNarrowing)
            _HeaderButton(
              key: LogPanel.clearKey,
              icon: Icons.filter_alt_off_outlined,
              tooltip: 'clear filters',
              onTap: controller.clearFilters,
            ),
          _HeaderButton(
            key: LogPanel.copyKey,
            icon: Icons.copy_all_outlined,
            tooltip: 'copy the visible log',
            onTap: () => unawaited(controller.copyVisible()),
          ),
          _HeaderButton(
            key: LogPanel.closeKey,
            icon: Icons.close,
            tooltip: 'close the log',
            onTap: controller.close,
          ),
        ],
      ),
    );
  }

  Widget _list(List<LogEntry> entries) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'no entries',
          style: PhiType.monoS().copyWith(color: PhiColors.fg3),
        ),
      );
    }
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: SelectionArea(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(vertical: PhiSpacing.s1),
              itemCount: entries.length,
              itemBuilder: (context, i) => LogEntryRow(entry: entries[i]),
            ),
          ),
        ),
        if (!_following)
          Positioned(
            right: PhiSpacing.s3,
            bottom: PhiSpacing.s3,
            child: _JumpToNewest(onTap: _jumpToNewest),
          ),
      ],
    );
  }
}

/// A compact icon button for the panel header.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s2),
            child: Icon(icon, size: 16, color: PhiColors.fg2),
          ),
        ),
      ),
    );
  }
}

/// The jump-to-newest pill, shown while follow is paused (design §4).
class _JumpToNewest extends StatelessWidget {
  const _JumpToNewest({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: LogPanel.jumpToNewestKey,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: PhiSpacing.s3,
            vertical: PhiSpacing.s1,
          ),
          decoration: BoxDecoration(
            color: PhiColors.bg3,
            borderRadius: PhiRadii.allPill,
            border: Border.all(color: PhiColors.line2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_downward, size: 12, color: PhiColors.fg1),
              const SizedBox(width: PhiSpacing.s1),
              Text(
                'jump to newest',
                style: PhiType.monoS().copyWith(color: PhiColors.fg1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
