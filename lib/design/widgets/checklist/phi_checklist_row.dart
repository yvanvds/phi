import 'package:flutter/material.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_motion.dart';
import '../../tokens/phi_radii.dart';
import '../../tokens/phi_spacing.dart';
import '../../tokens/phi_type.dart';

/// A Phi-themed checklist row: a [label] with a leading checkbox and an
/// optional [trailing] slot. Token-first and domain-free — the settings
/// dialog's MIDI input list drops an activity dot into [trailing].
///
/// The whole row is the hit target: tapping (anywhere) toggles [value] through
/// [onChanged]. A `null` [onChanged] renders the disabled state.
class PhiChecklistRow extends StatefulWidget {
  const PhiChecklistRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.trailing,
    super.key,
  });

  /// The row's text.
  final String label;

  /// Whether the checkbox is checked.
  final bool value;

  /// Called with the toggled value on tap. A `null` callback disables the row.
  final ValueChanged<bool>? onChanged;

  /// Optional widget pinned to the row's trailing edge (e.g. an activity dot).
  final Widget? trailing;

  @override
  State<PhiChecklistRow> createState() => _PhiChecklistRowState();
}

class _PhiChecklistRowState extends State<PhiChecklistRow> {
  bool _hovered = false;

  bool get _enabled => widget.onChanged != null;

  void _toggle() => widget.onChanged?.call(!widget.value);

  @override
  Widget build(BuildContext context) {
    final labelColor = _enabled ? PhiColors.fg1 : PhiColors.fg3;
    return MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _enabled ? _toggle : null,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s3),
          color: (_enabled && _hovered) ? PhiColors.bg2 : Colors.transparent,
          child: Row(
            children: [
              _checkbox(),
              const SizedBox(width: PhiSpacing.s3),
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: PhiType.body().copyWith(
                    fontSize: 14,
                    color: labelColor,
                  ),
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: PhiSpacing.s2),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _checkbox() {
    final checked = widget.value;
    final Color fill;
    final Color border;
    if (!_enabled) {
      fill = checked ? PhiColors.fg3 : PhiColors.bg1;
      border = checked ? PhiColors.fg3 : PhiColors.line1;
    } else {
      fill = checked ? PhiColors.voice1 : PhiColors.bg1;
      border = checked ? PhiColors.voice1 : PhiColors.line2;
    }

    return AnimatedContainer(
      duration: PhiMotion.dur1,
      curve: PhiMotion.easeOut,
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: PhiRadii.all1,
        border: Border.all(color: border),
        boxShadow: (checked && _enabled)
            ? const [BoxShadow(color: PhiColors.voice1Soft, blurRadius: 8)]
            : null,
      ),
      child: checked
          ? const Icon(Icons.check, size: 12, color: PhiColors.bg0)
          : null,
    );
  }
}
