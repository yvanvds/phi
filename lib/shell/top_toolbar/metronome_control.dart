import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/transport_button/transport_button.dart';
import '../../engine/state/metronome_controller.dart';
import 'metronome_popover.dart';

/// The toolbar metronome control (issue #262, design §4): a click toggle plus a
/// popover opener that summons the [MetronomePopover] (domain, meter, accent,
/// volume). Binds to the live [MetronomeController]; the click is performance
/// state, so nothing here is ever persisted.
class MetronomeControl extends StatefulWidget {
  const MetronomeControl({required this.controller, super.key});

  final MetronomeController controller;

  static const Key toggleKey = Key('MetronomeControl.toggle');
  static const Key popoverButtonKey = Key('MetronomeControl.popover');

  @override
  State<MetronomeControl> createState() => _MetronomeControlState();
}

class _MetronomeControlState extends State<MetronomeControl> {
  final _overlayController = OverlayPortalController();
  final _link = LayerLink();

  @override
  void dispose() {
    if (_overlayController.isShowing) _overlayController.hide();
    super.dispose();
  }

  void _togglePopover() {
    if (_overlayController.isShowing) {
      _overlayController.hide();
    } else {
      _overlayController.show();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final domainLabel = controller.domainName ?? 'session';
        return CompositedTransformTarget(
          link: _link,
          child: OverlayPortal(
            controller: _overlayController,
            overlayChildBuilder: _buildOverlay,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TransportButton(
                  key: MetronomeControl.toggleKey,
                  icon: Icons.av_timer,
                  tooltip: controller.enabled ? 'click on' : 'click off',
                  isActive: controller.enabled,
                  onPressed: controller.toggle,
                ),
                const SizedBox(width: PhiSpacing.s2),
                _PopoverButton(label: domainLabel, onTap: _togglePopover),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverlay(BuildContext context) {
    return Stack(
      children: [
        // A transparent barrier so an outside tap dismisses the popover; the
        // panel (and any picker overlay it opens above this) sits on top.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _overlayController.hide,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, PhiSpacing.s1),
          child: Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: Colors.transparent,
              child: MetronomePopover(controller: widget.controller),
            ),
          ),
        ),
      ],
    );
  }
}

/// The closed popover opener: a pill showing the bound domain + meter, opening
/// the [MetronomePopover] on tap.
class _PopoverButton extends StatelessWidget {
  const _PopoverButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: MetronomeControl.popoverButtonKey,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s2),
          decoration: BoxDecoration(
            color: PhiColors.bg2,
            borderRadius: PhiRadii.allPill,
            border: Border.all(color: PhiColors.line1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'click · $label',
                style: PhiType.monoS().copyWith(color: PhiColors.fg2),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 14,
                color: PhiColors.fg3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
