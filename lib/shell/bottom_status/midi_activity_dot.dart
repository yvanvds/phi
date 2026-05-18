import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';

/// Bottom-status MIDI activity indicator — a small voice-3 dot that flashes
/// briefly on each incoming MIDI message, then fades back to idle.
class MidiActivityDot extends StatefulWidget {
  const MidiActivityDot({
    required this.activity,
    super.key,
    this.flashDuration = const Duration(milliseconds: 120),
  });

  /// Tick stream — any emission triggers a flash.
  final Stream<void> activity;

  /// How long the dot stays lit after each tick.
  final Duration flashDuration;

  @override
  State<MidiActivityDot> createState() => _MidiActivityDotState();
}

class _MidiActivityDotState extends State<MidiActivityDot> {
  StreamSubscription<void>? _sub;
  Timer? _fade;
  bool _lit = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.activity.listen(_onTick);
  }

  @override
  void didUpdateWidget(MidiActivityDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activity != oldWidget.activity) {
      _sub?.cancel();
      _sub = widget.activity.listen(_onTick);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _fade?.cancel();
    super.dispose();
  }

  void _onTick(void _) {
    _fade?.cancel();
    if (!_lit) setState(() => _lit = true);
    _fade = Timer(widget.flashDuration, () {
      if (mounted) setState(() => _lit = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('MIDI', style: PhiType.caption().copyWith(color: PhiColors.fg3)),
          const SizedBox(width: PhiSpacing.s2),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _lit ? PhiColors.voice3 : PhiColors.fg4,
              shape: BoxShape.circle,
              boxShadow: _lit
                  ? const [
                      BoxShadow(color: PhiColors.voice3Soft, blurRadius: 8),
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
