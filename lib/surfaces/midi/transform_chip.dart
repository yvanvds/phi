import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/tokens/phi_voices.dart';
import '../../domain/midi/midi_transform.dart';

/// One row in the transform chain sidebar. 36px kind tag + label + 20×10
/// pill toggle. Active rows pick up the kind's voice colour and glow; the
/// pill animates whenever it switches state.
class TransformChip extends StatelessWidget {
  const TransformChip({
    required this.transform,
    required this.onToggle,
    super.key,
  });

  final MidiTransform transform;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final voice = transform.kind.voiceIndex;
    final color = PhiVoices.color(voice);
    final glow = PhiVoices.glow(voice);
    final active = transform.active;

    return Opacity(
      opacity: active ? 1 : 0.5,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: active ? PhiColors.bg2 : null,
            borderRadius: PhiRadii.all1,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  transform.kind.tag.toUpperCase(),
                  style: PhiType.monoS().copyWith(
                    fontSize: 8,
                    color: active ? color : PhiColors.fg3,
                    letterSpacing: 0.08 * 8,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  transform.label,
                  style: PhiType.monoS().copyWith(
                    fontSize: 11,
                    color: active ? PhiColors.fg0 : PhiColors.fg3,
                  ),
                ),
              ),
              _PillToggle(active: active, color: color, glow: glow),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillToggle extends StatelessWidget {
  const _PillToggle({
    required this.active,
    required this.color,
    required this.glow,
  });

  final bool active;
  final Color color;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 10,
      decoration: BoxDecoration(
        color: active ? color : PhiColors.fg4,
        borderRadius: PhiRadii.allPill,
        boxShadow: active ? [BoxShadow(color: glow, blurRadius: 6)] : null,
      ),
      child: AnimatedAlign(
        alignment: active ? Alignment.centerRight : Alignment.centerLeft,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: PhiColors.bg0,
              borderRadius: PhiRadii.allPill,
            ),
          ),
        ),
      ),
    );
  }
}
