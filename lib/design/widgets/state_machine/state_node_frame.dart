import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_type.dart';
import '../../tokens/phi_voices.dart';
import 'state_canvas_constants.dart';

/// Visual chrome for one state node: a rounded square with an uppercase
/// "STATE" caption, the state name beneath, and four voice-coloured corner
/// pins. Visual-only and unaware of [PerformanceState] /
/// [StateMachineController]; callers wrap it in a `GestureDetector`/
/// `Listener` for drag, tap, and transition authoring.
///
/// Layout mirrors `design system/preview/component-stategraph.html`'s
/// dormant state nodes (the "intro" / "drone" / "out" boxes). The "armed"
/// and "live" capsules arrive in #10b.
class StateNodeFrame extends StatelessWidget {
  const StateNodeFrame({required this.name, required this.voice, super.key});

  /// State name shown beneath the caption.
  final String name;

  /// Voice index in `[1, 6]` driving the corner-pin colour.
  final int voice;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: PhiColors.bg1,
            border: Border.all(color: PhiColors.line1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'STATE',
                  style: PhiType.caption().copyWith(
                    color: PhiColors.fg3,
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: PhiType.mono().copyWith(
                    color: PhiColors.fg1,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ),
        for (final corner in _CornerPin.values)
          Positioned(
            left: corner.isLeft ? -StateCanvasConstants.pinSize / 2 : null,
            right: corner.isLeft ? null : -StateCanvasConstants.pinSize / 2,
            top: corner.isTop ? -StateCanvasConstants.pinSize / 2 : null,
            bottom: corner.isTop ? null : -StateCanvasConstants.pinSize / 2,
            child: _Pin(voice: voice),
          ),
      ],
    );
  }
}

enum _CornerPin {
  topLeft(isLeft: true, isTop: true),
  topRight(isLeft: false, isTop: true),
  bottomLeft(isLeft: true, isTop: false),
  bottomRight(isLeft: false, isTop: false);

  const _CornerPin({required this.isLeft, required this.isTop});

  final bool isLeft;
  final bool isTop;
}

class _Pin extends StatelessWidget {
  const _Pin({required this.voice});

  final int voice;

  @override
  Widget build(BuildContext context) {
    final color = PhiVoices.color(voice);
    final glow = PhiVoices.glow(voice);
    return Container(
      width: StateCanvasConstants.pinSize,
      height: StateCanvasConstants.pinSize,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: glow, blurRadius: 6)],
      ),
    );
  }
}
