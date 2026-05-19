import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/midi/midi_transform_chain.dart';
import 'transform_chip.dart';

/// 250px right-hand sidebar listing the [MidiTransformChain]'s transforms.
/// Header has the panel title and a `+` placeholder; chip taps flip
/// `active` on the chain at that index.
class TransformChainPanel extends StatelessWidget {
  const TransformChainPanel({required this.chain, super.key});

  final MidiTransformChain chain;

  @override
  Widget build(BuildContext context) {
    final transforms = chain.transforms;
    return Container(
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        border: Border.all(color: PhiColors.line1),
        borderRadius: PhiRadii.all2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                for (var i = 0; i < transforms.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: TransformChip(
                      transform: transforms[i],
                      onToggle: () =>
                          chain.setActiveAt(i, !transforms[i].active),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PhiColors.line1)),
      ),
      child: Row(
        children: [
          Text(
            'transform chain'.toUpperCase(),
            style: PhiType.caption().copyWith(color: PhiColors.fg1),
          ),
          const Spacer(),
          // `+` is a no-op stub for the scaffold; gesture wiring follows
          // in the editing PR.
          Text('+', style: PhiType.monoS().copyWith(color: PhiColors.fg3)),
        ],
      ),
    );
  }
}
