import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/capsule/capsule.dart';

/// Top header above the piano roll: clip name, note count + meter caption,
/// the SMF import/export actions, and the two context capsules ("D dorian",
/// "domain · drum") from the mockup. Capsules are static for the scaffold —
/// wiring them to the live scale/time-domain state is a follow-up.
class MidiHeaderStrip extends StatelessWidget {
  const MidiHeaderStrip({
    required this.clipName,
    required this.noteCount,
    required this.bars,
    this.onImport,
    this.onExport,
    this.errorText,
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

    return Row(
      children: [
        Text('midi · $clipName'.toUpperCase(), style: PhiType.caption()),
        const SizedBox(width: 12),
        Expanded(child: caption),
        if (onImport != null) ...[
          _MidiIoButton(label: 'import', onTap: onImport!),
          const SizedBox(width: 6),
        ],
        if (onExport != null) ...[
          _MidiIoButton(label: 'export', onTap: onExport!),
          const SizedBox(width: 8),
        ],
        const Capsule(label: 'D dorian'),
        const SizedBox(width: 8),
        const Capsule(label: 'domain · drum', color: PhiColors.cool),
      ],
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
