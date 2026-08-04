import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_spacing.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../design/widgets/select/phi_select.dart';
import '../../../design/widgets/select/phi_select_option.dart';
import '../../../domain/project/entity_address.dart';
import '../../../engine/state/patch_library_controller.dart';

/// The Patcher surface's **source-placement bar** (issue #224, design
/// `docs/design/patcher.md` §4 role 1) — the thin strip above the canvas that
/// mounts the open patch as a `Sound` on a mix bus and starts / stops it.
///
/// - A [PhiSelect] over the placeable mix buses ([PatchLibraryController.busOptions])
///   sets the source placement; picking a bus records it in the payload so it
///   persists. A `×` clears the placement.
/// - A **start / stop** toggle mounts / unmounts the source. Placement persists;
///   running state does not (a loaded project starts silent), so the toggle
///   always reads *stopped* on open. It is disabled while the patch is unplaced.
/// - A **snap-to-grid** toggle for the canvas below (issue #368) — the one
///   canvas preference that needs somewhere to live, and this strip is the
///   patcher's only chrome, exactly as the piano roll's snap picker sits in its
///   header. A view preference, so it is held by the surface and lost on
///   restart rather than written into the patch.
///
/// A thin, [ChangeNotifier]-bound view of the [PatchLibraryController]. Renders a
/// low-key hint when no patch is open.
class PatchPlacementBar extends StatelessWidget {
  const PatchPlacementBar({
    required this.controller,
    this.snapToGrid = false,
    this.onSnapChanged,
    super.key,
  });

  final PatchLibraryController controller;

  /// Whether the canvas quantises a node drop to the grid. Reflected by the
  /// [snapKey] toggle, which is hidden entirely when [onSnapChanged] is null —
  /// a control nobody is listening to would be a lie.
  final bool snapToGrid;

  /// Called with the requested new value when the snap toggle is tapped.
  final ValueChanged<bool>? onSnapChanged;

  /// Key on the bus-placement select.
  static const Key placeSelectKey = Key('PatchPlacementBar.place');

  /// Key on the start / stop toggle.
  static const Key startStopKey = Key('PatchPlacementBar.startStop');

  /// Key on the clear-placement (`×`) button, present only while placed.
  static const Key unplaceKey = Key('PatchPlacementBar.unplace');

  /// Key on the canvas grid-snap toggle (issue #368).
  static const Key snapKey = Key('PatchPlacementBar.snap');

  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final open = controller.openAddress;
        return Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s3),
          decoration: const BoxDecoration(
            color: PhiColors.bg1,
            border: Border(bottom: BorderSide(color: PhiColors.line1)),
          ),
          child: open == null ? _hint() : _controls(context, open),
        );
      },
    );
  }

  Widget _hint() {
    return Row(
      children: [
        Text(
          'no patch open'.toUpperCase(),
          style: PhiType.caption().copyWith(color: PhiColors.fg3),
        ),
      ],
    );
  }

  Widget _controls(BuildContext context, EntityAddress open) {
    final placement = controller.placementOf(open);
    final running = controller.isRunning(open);
    final options = controller.busOptions();
    return Row(
      children: [
        Text(
          'src ›'.toUpperCase(),
          style: PhiType.caption().copyWith(color: PhiColors.fg2),
        ),
        const SizedBox(width: PhiSpacing.s2),
        // Flexible so the bar degrades gracefully in a narrow docked pane
        // (issue #287) rather than overflowing.
        Expanded(
          child: PhiSelect<EntityAddress>.flat(
            key: placeSelectKey,
            value: placement,
            placeholder: 'place on a bus…',
            options: [
              for (final bus in options)
                PhiSelectOption<EntityAddress>(
                  value: bus.address,
                  label: bus.label,
                ),
            ],
            onChanged: (bus) => controller.place(open, bus),
          ),
        ),
        if (placement != null)
          Padding(
            padding: const EdgeInsets.only(left: PhiSpacing.s1),
            child: _IconButton(
              buttonKey: unplaceKey,
              icon: Icons.close,
              tooltip: 'unplace',
              onTap: () => controller.unplace(open),
            ),
          ),
        const SizedBox(width: PhiSpacing.s2),
        _StartStopButton(
          running: running,
          enabled: placement != null,
          onTap: () => running ? controller.stop(open) : controller.start(open),
        ),
        if (onSnapChanged != null) ...[
          const SizedBox(width: PhiSpacing.s2),
          _SnapButton(on: snapToGrid, onTap: () => onSnapChanged!(!snapToGrid)),
        ],
      ],
    );
  }
}

/// The canvas grid-snap toggle (issue #368) — lit while a node drop quantises
/// to the grid.
class _SnapButton extends StatelessWidget {
  const _SnapButton({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = on ? PhiColors.voice1 : PhiColors.fg2;
    return Tooltip(
      message: on ? 'grid snap on' : 'grid snap off',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: PatchPlacementBar.snapKey,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.grid_4x4, size: 16, color: fg),
              const SizedBox(width: PhiSpacing.s0),
              Text(
                'snap'.toUpperCase(),
                style: PhiType.caption().copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The start / stop transport toggle for the placed source.
class _StartStopButton extends StatelessWidget {
  const _StartStopButton({
    required this.running,
    required this.enabled,
    required this.onTap,
  });

  final bool running;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fg;
    if (!enabled) {
      fg = PhiColors.fg3;
    } else if (running) {
      fg = PhiColors.voice1;
    } else {
      fg = PhiColors.fg1;
    }
    return Tooltip(
      message: !enabled
          ? 'place on a bus to start'
          : running
          ? 'stop source'
          : 'start source',
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          key: PatchPlacementBar.startStopKey,
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                running ? Icons.stop : Icons.play_arrow,
                size: 16,
                color: fg,
              ),
              const SizedBox(width: PhiSpacing.s0),
              Text(
                (running ? 'stop' : 'start').toUpperCase(),
                style: PhiType.caption().copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact square icon button styled to the bar's chrome.
class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.buttonKey,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: buttonKey,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 22,
            height: 22,
            child: Icon(icon, size: 14, color: PhiColors.fg2),
          ),
        ),
      ),
    );
  }
}
