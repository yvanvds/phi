import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_motion.dart';
import '../../tokens/phi_radii.dart';
import '../../tokens/phi_spacing.dart';
import '../../tokens/phi_type.dart';
import 'phi_select_group.dart';
import 'phi_select_option.dart';

/// A Phi-themed dropdown select. Token-first and domain-free — the first
/// consumer is the settings dialog (device / rate / buffer / layout pickers),
/// with transform and voice pickers to follow.
///
/// Options arrive as [groups]: a flat list is one headerless group (use
/// [PhiSelect.flat]); a grouped list — audio devices grouped by host — is
/// several groups each carrying a header. A "device default" first entry is
/// just an ordinary option whose value the consumer chooses.
///
/// The closed control shows the selected option's label (or [placeholder] when
/// [value] matches no option). Tapping — or ArrowDown / Enter / Space while
/// focused — opens an overlay list; ArrowUp/Down move the highlight (skipping
/// headers), Enter/Space commit it, Escape or an outside tap dismiss. The
/// widget is [enabled] by default; passing a `null` [onChanged] or
/// `enabled: false` renders the disabled state.
class PhiSelect<T> extends StatefulWidget {
  const PhiSelect({
    required this.value,
    required this.groups,
    required this.onChanged,
    this.placeholder = 'select…',
    this.enabled = true,
    super.key,
  });

  /// Convenience for the common flat (ungrouped) case: wraps [options] in a
  /// single headerless [PhiSelectGroup].
  PhiSelect.flat({
    required this.value,
    required List<PhiSelectOption<T>> options,
    required this.onChanged,
    this.placeholder = 'select…',
    this.enabled = true,
    super.key,
  }) : groups = [PhiSelectGroup<T>(options: options)];

  /// The currently selected value, or `null` when nothing is selected.
  final T? value;

  /// The option groups to offer, in display order.
  final List<PhiSelectGroup<T>> groups;

  /// Called with the picked value. A `null` callback disables the control.
  final ValueChanged<T>? onChanged;

  /// Text shown in the closed control when [value] matches no option.
  final String placeholder;

  /// Whether the control accepts input. Combined with [onChanged] being set.
  final bool enabled;

  @override
  State<PhiSelect<T>> createState() => _PhiSelectState<T>();
}

class _PhiSelectState<T> extends State<PhiSelect<T>> {
  final _overlayController = OverlayPortalController();
  final _link = LayerLink();
  final _focusNode = FocusNode(debugLabel: 'PhiSelect');

  bool _open = false;
  bool _hovered = false;
  int _highlighted = 0;

  bool get _interactive =>
      widget.enabled && widget.onChanged != null && _flatOptions.isNotEmpty;

  List<PhiSelectOption<T>> get _flatOptions => [
    for (final g in widget.groups) ...g.options,
  ];

  int _indexOfValue(T? value) {
    final options = _flatOptions;
    for (var i = 0; i < options.length; i++) {
      if (options[i].value == value) return i;
    }
    return -1;
  }

  String? get _selectedLabel {
    final i = _indexOfValue(widget.value);
    return i < 0 ? null : _flatOptions[i].label;
  }

  @override
  void dispose() {
    if (_overlayController.isShowing) _overlayController.hide();
    _focusNode.dispose();
    super.dispose();
  }

  void _openMenu() {
    final selected = _indexOfValue(widget.value);
    setState(() {
      _open = true;
      _highlighted = selected < 0 ? 0 : selected;
    });
    _overlayController.show();
    _focusNode.requestFocus();
  }

  void _closeMenu() {
    if (!_open) return;
    setState(() => _open = false);
    _overlayController.hide();
  }

  void _toggleMenu() => _open ? _closeMenu() : _openMenu();

  void _select(T value) {
    widget.onChanged?.call(value);
    _closeMenu();
  }

  void _moveHighlight(int delta) {
    final count = _flatOptions.length;
    if (count == 0) return;
    setState(() => _highlighted = (_highlighted + delta).clamp(0, count - 1));
  }

  void _commitHighlighted() {
    final options = _flatOptions;
    if (_highlighted >= 0 && _highlighted < options.length) {
      _select(options[_highlighted].value);
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_interactive) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (!_open) {
      if (key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.space) {
        _openMenu();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      _commitHighlighted();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _closeMenu();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      _closeMenu();
      return KeyEventResult.ignored; // let focus traversal continue
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: _buildOverlay,
      child: CompositedTransformTarget(
        link: _link,
        child: Focus(
          focusNode: _focusNode,
          onKeyEvent: _handleKey,
          child: MouseRegion(
            cursor: _interactive
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _interactive ? _toggleMenu : null,
              child: _buildControl(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControl() {
    final Color background;
    final Color border;
    if (!_interactive) {
      background = PhiColors.bg1;
      border = PhiColors.line1;
    } else if (_open) {
      background = PhiColors.bg3;
      border = PhiColors.lineHot;
    } else if (_hovered || _focusNode.hasFocus) {
      background = PhiColors.bg3;
      border = PhiColors.line2;
    } else {
      background = PhiColors.bg2;
      border = PhiColors.line1;
    }

    final label = _selectedLabel;
    final Color textColor;
    if (!_interactive) {
      textColor = PhiColors.fg3;
    } else if (label == null) {
      textColor = PhiColors.fg2;
    } else {
      textColor = PhiColors.fg0;
    }

    return AnimatedContainer(
      duration: PhiMotion.dur1,
      curve: PhiMotion.easeOut,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: PhiRadii.all2,
        border: Border.all(color: border),
        boxShadow: _open
            ? const [BoxShadow(color: PhiColors.voice1Soft, blurRadius: 10)]
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label ?? widget.placeholder,
              overflow: TextOverflow.ellipsis,
              style: PhiType.body().copyWith(fontSize: 14, color: textColor),
            ),
          ),
          const SizedBox(width: PhiSpacing.s2),
          AnimatedRotation(
            turns: _open ? 0.5 : 0,
            duration: PhiMotion.dur2,
            curve: PhiMotion.easeOut,
            child: Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: _interactive ? PhiColors.fg2 : PhiColors.fg3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final width = _link.leaderSize?.width ?? 0;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _closeMenu,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, PhiSpacing.s1),
          child: Align(alignment: Alignment.topLeft, child: _buildMenu(width)),
        ),
      ],
    );
  }

  Widget _buildMenu(double width) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          minWidth: width,
          maxWidth: width == 0 ? double.infinity : width,
          maxHeight: 280,
        ),
        decoration: BoxDecoration(
          color: PhiColors.bg2,
          borderRadius: PhiRadii.all2,
          border: Border.all(color: PhiColors.line2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: PhiRadii.all2,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _rows(),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _rows() {
    final rows = <Widget>[];
    var index = 0;
    for (final group in widget.groups) {
      final header = group.label;
      if (header != null) rows.add(_header(header));
      for (final option in group.options) {
        rows.add(_optionRow(option, index));
        index++;
      }
    }
    return rows;
  }

  Widget _header(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PhiSpacing.s3,
        PhiSpacing.s2,
        PhiSpacing.s3,
        PhiSpacing.s1,
      ),
      child: Text(label.toUpperCase(), style: PhiType.caption()),
    );
  }

  Widget _optionRow(PhiSelectOption<T> option, int index) {
    final highlighted = index == _highlighted;
    final selected = option.value == widget.value;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _highlighted = index),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(option.value),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s3),
          color: highlighted ? PhiColors.bg3 : Colors.transparent,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option.label,
                  overflow: TextOverflow.ellipsis,
                  style: PhiType.body().copyWith(
                    fontSize: 14,
                    color: selected ? PhiColors.voice1 : PhiColors.fg1,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check, size: 16, color: PhiColors.voice1),
            ],
          ),
        ),
      ),
    );
  }
}
