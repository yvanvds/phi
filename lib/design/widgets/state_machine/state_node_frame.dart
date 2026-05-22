import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_type.dart';
import '../../tokens/phi_voices.dart';
import 'state_canvas_constants.dart';

/// Visual chrome for one state node: a rounded square with a status
/// caption, the state name beneath, and four voice-coloured corner
/// pins. Visual-only and unaware of [PerformanceState] /
/// [StateMachineController]; callers wrap it in a `GestureDetector`/
/// `Listener` for drag, tap, and transition authoring.
///
/// Three [display] modes — `idle`, `live`, `armed` — drive border /
/// caption / glow per
/// `design system/preview/component-stategraph.html`. `idle` mirrors the
/// dormant "intro" / "drone" / "out" boxes; `live` mirrors the active
/// fuchsia-bordered "verse" node; `armed` mirrors the amber-bordered
/// "break" node with its `▲ ARMED · 4 BARS` capsule.
class StateNodeFrame extends StatelessWidget {
  const StateNodeFrame({
    required this.name,
    required this.voice,
    this.display = StateNodeDisplay.idle,
    this.armedLabel,
    super.key,
  });

  /// State name shown beneath the caption.
  final String name;

  /// Voice index in `[1, 6]` driving the corner-pin colour.
  final int voice;

  /// Which capsule to render. [armedLabel] is consumed only when
  /// [display] is [StateNodeDisplay.armed].
  final StateNodeDisplay display;

  /// Free-form `fireOn` label shown in the armed capsule (e.g. "manual",
  /// "4 bars"). Ignored unless [display] is [StateNodeDisplay.armed];
  /// rendered uppercase per the design preview.
  final String? armedLabel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: PhiColors.bg1,
            border: Border.all(color: _borderColor()),
            borderRadius: BorderRadius.circular(4),
            boxShadow: _glow(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _captionText(),
                  style: PhiType.caption().copyWith(
                    color: _captionColor(),
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: PhiType.mono().copyWith(
                    color: display == StateNodeDisplay.idle
                        ? PhiColors.fg1
                        : PhiColors.fg0,
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

  Color _borderColor() => switch (display) {
    StateNodeDisplay.idle => PhiColors.line1,
    StateNodeDisplay.live => PhiColors.lineHot,
    // Mirrors the preview's `rgba(255,180,84,0.5)` border tint —
    // voice-3 (amber) at 50% alpha.
    StateNodeDisplay.armed => PhiColors.voice3.withValues(alpha: 0.5),
  };

  Color _captionColor() => switch (display) {
    StateNodeDisplay.idle => PhiColors.fg3,
    StateNodeDisplay.live => PhiColors.voice1,
    StateNodeDisplay.armed => PhiColors.voice3,
  };

  String _captionText() => switch (display) {
    StateNodeDisplay.idle => 'STATE',
    StateNodeDisplay.live => '● LIVE',
    StateNodeDisplay.armed => '▲ ARMED · ${(armedLabel ?? '').toUpperCase()}',
  };

  List<BoxShadow>? _glow() => switch (display) {
    StateNodeDisplay.idle => null,
    StateNodeDisplay.live => const [
      BoxShadow(color: PhiColors.voice1Soft, blurRadius: 16),
    ],
    StateNodeDisplay.armed => const [
      BoxShadow(color: PhiColors.voice3Soft, blurRadius: 16),
    ],
  };
}

/// Visual mode for the state-node header.
enum StateNodeDisplay {
  /// No special status — neutral caption + line border.
  idle,

  /// This state is currently active. Fuchsia caption + hot border + glow.
  live,

  /// An incoming transition is armed. Amber caption (with the
  /// transition's `fireOn` label) + amber border + glow.
  armed,
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
