import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import 'command_match.dart';
import 'command_registry.dart';
import 'command_search.dart';

/// The command palette overlay (design `docs/design/shell-layout.md` §4): a
/// top-anchored search box over the [CommandRegistry] opened on Ctrl+Shift+P /
/// F1. Fuzzy search over title + category, recently-used first, the shortcut
/// shown per row, arrow-key navigation, disabled commands hidden. Executing a
/// command routes through [CommandRegistry.invoke] — the same code path as its
/// menu/button equivalent — so the palette is a launcher, never a second
/// implementation.
class CommandPalette extends StatefulWidget {
  const CommandPalette({required this.registry, super.key});

  final CommandRegistry registry;

  /// Opens the palette as a modal overlay over [context]. Resolves when it is
  /// dismissed (invoking a command pops it first, then runs the command).
  static Future<void> show(
    BuildContext context, {
    required CommandRegistry registry,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (_) => CommandPalette(registry: registry),
    );
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  static const double _rowHeight = 46;

  final TextEditingController _query = TextEditingController();
  final FocusNode _fieldFocus = FocusNode(debugLabel: 'commandPaletteField');
  final ScrollController _scroll = ScrollController();

  late List<CommandMatch> _results = _search('');
  int _highlighted = 0;

  List<CommandMatch> _search(String query) => CommandSearch.run(
    query,
    widget.registry.enabledCommands,
    recentIds: widget.registry.recentIds,
  );

  @override
  void dispose() {
    _query.dispose();
    _fieldFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {
      _results = _search(value);
      _highlighted = 0;
    });
    _ensureHighlightVisible();
  }

  /// Intercepts navigation keys before the text field's own editing shortcuts —
  /// handled on the field's focus node, which fires ahead of `EditableText`, so
  /// typing still reaches the field while arrows/enter/escape drive the list.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _invokeAt(_highlighted);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _move(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _highlighted = (_highlighted + delta).clamp(0, _results.length - 1);
    });
    _ensureHighlightVisible();
  }

  void _ensureHighlightVisible() {
    if (!_scroll.hasClients) return;
    final target = _highlighted * _rowHeight;
    final top = _scroll.offset;
    final bottom = top + _scroll.position.viewportDimension;
    if (target < top) {
      _scroll.jumpTo(target);
    } else if (target + _rowHeight > bottom) {
      _scroll.jumpTo(target + _rowHeight - _scroll.position.viewportDimension);
    }
  }

  void _invokeAt(int index) {
    if (index < 0 || index >= _results.length) return;
    final id = _results[index].command.id;
    // Pop first so the command's own navigation (a dialog, a surface summon)
    // runs over the workstation, not under this overlay.
    Navigator.of(context).pop();
    widget.registry.invoke(id);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.55),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s5),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 560,
            constraints: const BoxConstraints(maxHeight: 440),
            decoration: BoxDecoration(
              color: PhiColors.bg1,
              borderRadius: PhiRadii.all3,
              border: Border.all(color: PhiColors.line2),
              boxShadow: const [
                BoxShadow(color: Color(0x66000000), blurRadius: 32),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(),
                const Divider(height: 1, thickness: 1, color: PhiColors.line1),
                Flexible(child: _resultsList()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PhiSpacing.s4,
        vertical: PhiSpacing.s2,
      ),
      child: Row(
        children: [
          const Icon(Icons.chevron_right, size: 18, color: PhiColors.fg2),
          const SizedBox(width: PhiSpacing.s2),
          Expanded(
            child: Focus(
              onKeyEvent: _onKey,
              child: TextField(
                controller: _query,
                focusNode: _fieldFocus,
                autofocus: true,
                onChanged: _onQueryChanged,
                style: PhiType.body().copyWith(color: PhiColors.fg0),
                cursorColor: PhiColors.voice1,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Type a command…',
                  hintStyle: PhiType.body().copyWith(color: PhiColors.fg3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultsList() {
    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(PhiSpacing.s5),
        child: Text(
          'No matching commands',
          style: PhiType.monoS().copyWith(color: PhiColors.fg3),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: PhiSpacing.s1),
      itemExtent: _rowHeight,
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final match = _results[index];
        return _CommandRow(
          match: match,
          selected: index == _highlighted,
          onTap: () => _invokeAt(index),
          onHover: () {
            if (_highlighted != index) {
              setState(() => _highlighted = index);
            }
          },
        );
      },
    );
  }
}

/// One command row: title (matched chars highlighted), category, and — right —
/// the shortcut chord when the command carries one.
class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.match,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final CommandMatch match;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final command = match.command;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s4),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: selected ? PhiColors.bg2 : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: selected ? PhiColors.voice1 : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _title(),
                    const SizedBox(height: 2),
                    Text(
                      command.category,
                      style: PhiType.monoS().copyWith(color: PhiColors.fg3),
                    ),
                  ],
                ),
              ),
              if (command.shortcut != null) ...[
                const SizedBox(width: PhiSpacing.s3),
                _ShortcutChip(label: command.shortcut!.label),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _title() {
    final title = match.command.title;
    final matched = match.matchedTitleIndices;
    final base = PhiType.body().copyWith(
      color: selected ? PhiColors.fg0 : PhiColors.fg1,
    );
    if (matched.isEmpty) {
      return Text(
        title,
        style: base,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    final highlight = base.copyWith(
      color: PhiColors.voice1,
      fontWeight: FontWeight.w600,
    );
    // `Text.rich` (not a bare `RichText`) so the row's title still resolves to
    // its plain text for `find.text` and screen readers, while matched glyphs
    // paint in the accent colour.
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < title.length; i++)
            TextSpan(
              text: title[i],
              style: matched.contains(i) ? highlight : base,
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _ShortcutChip extends StatelessWidget {
  const _ShortcutChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PhiSpacing.s2,
        vertical: PhiSpacing.s0,
      ),
      decoration: BoxDecoration(
        color: PhiColors.bg0,
        borderRadius: PhiRadii.all2,
        border: Border.all(color: PhiColors.line1),
      ),
      child: Text(label, style: PhiType.monoS().copyWith(color: PhiColors.fg2)),
    );
  }
}
