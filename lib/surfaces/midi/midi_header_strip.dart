import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/capsule/capsule.dart';
import '../../design/widgets/select/phi_select.dart';
import 'snap_grid.dart';

/// Top header above the piano roll: clip name, note count + meter caption, the
/// snap-grid picker (issue #189), the SMF import/export actions, and the two
/// context capsules ("D dorian", "domain · drum") from the mockup. Capsules are
/// static for the scaffold — wiring them to the live scale/time-domain state is
/// a follow-up.
class MidiHeaderStrip extends StatelessWidget {
  const MidiHeaderStrip({
    required this.clipName,
    required this.noteCount,
    required this.bars,
    this.onImport,
    this.onExport,
    this.errorText,
    this.gridDivision,
    this.onGridChanged,
    super.key,
  });

  final String clipName;
  final int noteCount;
  final int bars;

  /// Import/export handlers. When null the corresponding button is hidden —
  /// e.g. a preview with no file-IO wired.
  final VoidCallback? onImport;
  final VoidCallback? onExport;

  /// Transient error (e.g. a dropped file that wasn't valid SMF). Rendered in
  /// place of the caption in the alert colour when set.
  final String? errorText;

  /// The editor's current snap step in beats (issue #189). Paired with
  /// [onGridChanged]; when either is null the snap picker is hidden.
  final double? gridDivision;

  /// Called when the performer picks a new snap value from the header select.
  final ValueChanged<double>? onGridChanged;

  /// Key on the header's snap-grid picker, so tests can drive it.
  static const Key snapPickerKey = Key('MidiHeaderStrip.snapPicker');

  @override
  Widget build(BuildContext context) {
    final caption = errorText == null
        ? Text(
            '$noteCount notes · $bars bars · interpreted, not played',
            style: PhiType.monoS().copyWith(color: PhiColors.fg3),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          )
        : Text(
            errorText!,
            style: PhiType.monoS().copyWith(color: PhiColors.hot),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          );

    final onGrid = onGridChanged;
    final row = Row(
      children: [
        Text('midi · $clipName'.toUpperCase(), style: PhiType.caption()),
        const SizedBox(width: 8),
        Expanded(child: caption),
        if (onGrid != null) ...[
          _SnapPicker(value: gridDivision ?? SnapGrid.off, onChanged: onGrid),
          const SizedBox(width: 6),
        ],
        if (onImport != null) ...[
          _MidiIoButton(label: 'import', onTap: onImport!),
          const SizedBox(width: 6),
        ],
        if (onExport != null) ...[
          _MidiIoButton(label: 'export', onTap: onExport!),
          const SizedBox(width: 6),
        ],
        const Capsule(label: 'D dorian'),
        const SizedBox(width: 6),
        const Capsule(label: 'domain · drum', color: PhiColors.cool),
      ],
    );

    // Docked in a pane narrower than its content (issue #287), the header
    // scrolls horizontally instead of asserting a `RenderFlex overflowed`.
    // `IntrinsicWidth` gives the `Expanded` caption a bounded width to divide
    // (the row's natural width), while `minWidth: maxWidth` keeps the row
    // filling — and the trailing capsules pinned right — whenever the pane is
    // wide enough, so the common maximized layout is unchanged.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: IntrinsicWidth(child: row),
        ),
      ),
    );
  }
}

/// The header snap-grid picker (issue #189): a compact [PhiSelect] over the
/// [SnapGrid] options, feeding `ClipEditor.gridDivision`. The closed control
/// shows the current resolution (`1/16`, `1/8T`, `off`, …), so it reads as the
/// snap control without a separate label crowding the busy header.
class _SnapPicker extends StatelessWidget {
  const _SnapPicker({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: PhiSelect<double>.flat(
        key: MidiHeaderStrip.snapPickerKey,
        value: value,
        options: SnapGrid.options,
        onChanged: onChanged,
      ),
    );
  }
}

/// Small mono-labelled pill button matching the surface's capsule language,
/// used for the import/export actions.
class _MidiIoButton extends StatelessWidget {
  const _MidiIoButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: PhiColors.bg2,
            borderRadius: PhiRadii.allPill,
            border: Border.all(color: PhiColors.fg3.withValues(alpha: 0.4)),
          ),
          alignment: Alignment.center,
          child: Text(
            label.toUpperCase(),
            style: PhiType.mono().copyWith(
              color: PhiColors.fg2,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.08 * 10,
            ),
          ),
        ),
      ),
    );
  }
}
