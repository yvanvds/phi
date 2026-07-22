import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/log/log_level.dart';
import '../../domain/log/log_source.dart';
import 'log_panel_controller.dart';

/// The log panel's filter row (design `docs/design/diagnostics.md` §4): a
/// level selector (this level and above), a source toggle per stream, and a
/// text search — all combinable, all driving the [LogPanelController]'s filter.
class LogFilterBar extends StatefulWidget {
  /// Binds to [controller], whose filter these controls read and write.
  const LogFilterBar({required this.controller, super.key});

  /// The panel controller owning the live [filter].
  final LogPanelController controller;

  /// Key for the search field, so tests can target it unambiguously.
  static const Key searchFieldKey = Key('LogPanel.search');

  @override
  State<LogFilterBar> createState() => _LogFilterBarState();
}

class _LogFilterBarState extends State<LogFilterBar> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.controller.filter.query);
    // Keep the field in step when the query is reset from elsewhere (clear
    // filters, open-to-errors) without stomping the caret while the user types.
    widget.controller.addListener(_syncSearch);
  }

  void _syncSearch() {
    final query = widget.controller.filter.query;
    if (query != _search.text) _search.text = query;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncSearch);
    _search.dispose();
    super.dispose();
  }

  static Color _levelColor(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return PhiColors.hot;
      case LogLevel.warning:
        return PhiColors.warm;
      case LogLevel.info:
        return PhiColors.cool;
      case LogLevel.debug:
        return PhiColors.fg2;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.controller.filter;
    return Row(
      children: [
        Text('LEVEL', style: PhiType.caption()),
        const SizedBox(width: PhiSpacing.s2),
        for (final level in LogLevel.values)
          Padding(
            padding: const EdgeInsets.only(right: PhiSpacing.s1),
            child: _Chip(
              label: level.wireName,
              color: _levelColor(level),
              // "This level and above": a chip reads as active when the current
              // minimum would let it through.
              active: level.isAtLeast(filter.minLevel),
              onTap: () => widget.controller.setMinLevel(level),
            ),
          ),
        const SizedBox(width: PhiSpacing.s4),
        Text('SOURCE', style: PhiType.caption()),
        const SizedBox(width: PhiSpacing.s2),
        for (final source in LogSource.values)
          Padding(
            padding: const EdgeInsets.only(right: PhiSpacing.s1),
            child: _Chip(
              label: source.wireName,
              color: PhiColors.fg1,
              active: filter.sources.contains(source),
              onTap: () => widget.controller.toggleSource(source),
            ),
          ),
        const SizedBox(width: PhiSpacing.s4),
        Expanded(
          child: SizedBox(
            height: 26,
            child: TextField(
              key: LogFilterBar.searchFieldKey,
              controller: _search,
              onChanged: widget.controller.setQuery,
              style: PhiType.monoS().copyWith(color: PhiColors.fg1),
              cursorColor: PhiColors.voice1,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: PhiColors.bg0,
                hintText: 'search…',
                hintStyle: PhiType.monoS().copyWith(color: PhiColors.fg3),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 14,
                  color: PhiColors.fg3,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 26,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: PhiSpacing.s2,
                  vertical: PhiSpacing.s1,
                ),
                border: const OutlineInputBorder(
                  borderRadius: PhiRadii.all2,
                  borderSide: BorderSide(color: PhiColors.line1),
                ),
                enabledBorder: const OutlineInputBorder(
                  borderRadius: PhiRadii.all2,
                  borderSide: BorderSide(color: PhiColors.line1),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: PhiRadii.all2,
                  borderSide: BorderSide(color: PhiColors.line2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A small pill toggle used for both level and source filters — tinted and lit
/// when [active], dimmed when not.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: PhiSpacing.s2,
            vertical: PhiSpacing.s0,
          ),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.16) : PhiColors.bg0,
            borderRadius: PhiRadii.allPill,
            border: Border.all(
              color: active ? color.withValues(alpha: 0.6) : PhiColors.line1,
            ),
          ),
          child: Text(
            label.toUpperCase(),
            style: PhiType.monoS().copyWith(
              color: active ? color : PhiColors.fg3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
